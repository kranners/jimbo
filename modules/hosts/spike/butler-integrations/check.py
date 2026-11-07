"""butler-integration-check: one cheap, read-only live call per Butler integration, with its real credentials.

Run on spike as `butler` every 6 hours, a few minutes after butler starts and on Butler's `integrations run`.
Each check makes one read, with a timeout, and classes the integration as pass, warn (degraded, rate limited, a
credential expiring within 14 days), fail (with a one-line cause and the exact fix), not connected (Aaron has not
logged in yet, never told) or off (not enabled here).
Nothing here sends, posts, pays or changes anything: the writers are checked only for their approval gate in the
command manifest. Results go to the status file Butler's `integrations` command and the monitor read, and Aaron is
told once, through butler-notify, of what newly fails or expires soon.
The judging, the alert choice and the wording are pure functions, so the tests drive them with fake results.
"""

import base64
import concurrent.futures
import datetime
import json
import os
import re
import socket
import sqlite3
import ssl
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import zipfile

CONFIG = {}
DAY = 86400
EXPIRY_DAYS = 14
STATUSES = ("pass", "warn", "fail", "not connected", "off")
CHECKS = {}
TRANSIENT = re.compile(r"timed out|timeout|temporar|unreachable|connection (refused|reset)|name resolution|HTTP (429|5\d\d)|try again|could not be reached|could not reach|HTTP 0\b|network", re.I)


# ---------------------------------------------------------------- results and redaction

def result(status, cause="", fix="", expires=None, detail=None):
    return {"status": status, "cause": redact(cause), "fix": fix, "expires": expires, "detail": detail}


def ok(cause="", expires=None, detail=None):
    return result("pass", cause, expires=expires, detail=detail)


def warn(cause, fix="", expires=None):
    return result("warn", cause, fix, expires)


def fail(cause, fix=""):
    # A failure that looks like the network or the service having a bad moment is degraded, not broken.
    if TRANSIENT.search(cause or ""):
        return result("warn", cause + " (looks temporary)", fix)
    return result("fail", cause, fix)


def unconnected(cause, fix):
    return result("not connected", cause, fix)


SECRETS = [
    re.compile(r"\b(xox[a-z]-[A-Za-z0-9-]+)"),
    re.compile(r"\b(sk-[A-Za-z0-9_-]{8,})"),
    re.compile(r"\b(gh[pousr]_[A-Za-z0-9]{8,}|github_pat_[A-Za-z0-9_]{8,})"),
    re.compile(r"(?i)(bearer|token|key|secret|password)([=: \"']+)(?=[^\s\"',]*\d)[^\s\"',]{16,}"),
    re.compile(r"\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9._-]+"),
    re.compile(r"\b(?=[A-Za-z0-9_-]*\d)(?=[A-Za-z0-9_-]*[A-Za-z])[A-Za-z0-9_-]{32,}"),
    re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"),
]


def redact(text):
    """One plain line, cut at 240 characters, with anything shaped like a secret or an address cut."""
    text = " ".join(str(text or "").split())
    for pattern in SECRETS:
        text = pattern.sub(lambda m: (m.group(1) + m.group(2) + "[cut]") if pattern.groups == 2 else "[cut]", text)
    return text[:240]


# ---------------------------------------------------------------- helpers

def credential(name):
    """A credential this unit loaded, or "" when it is missing or empty, which means not connected."""
    directory = os.environ.get("CREDENTIALS_DIRECTORY", "")
    try:
        with open(os.path.join(directory, name)) as f:
            return f.read().strip()
    except OSError:
        return ""


def http(method, url, headers=None, data=None, timeout=20):
    """(status, headers, body), never raising for an HTTP status; status 0 with the reason when it never answered."""
    if isinstance(data, dict):
        data = json.dumps(data).encode()
    request = urllib.request.Request(url, data=data, method=method, headers={"User-Agent": "butler-integration-check/1 (read-only)", **(headers or {})})
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return response.status, {k.lower(): v for k, v in response.headers.items()}, response.read(2_000_000)
    except urllib.error.HTTPError as e:
        return e.code, {k.lower(): v for k, v in (e.headers or {}).items()}, e.read(20_000)
    except (urllib.error.URLError, OSError, ValueError) as e:
        return 0, {}, str(getattr(e, "reason", e)).encode()


def jbody(body):
    try:
        return json.loads(body)
    except (ValueError, TypeError):
        return None


def run(args, timeout=50, env=None):
    try:
        p = subprocess.run(args, capture_output=True, text=True, timeout=timeout, env={**os.environ, **(env or {})})
        return p.returncode, p.stdout, p.stderr
    except subprocess.TimeoutExpired:
        return 124, "", "timed out after %d seconds" % timeout
    except OSError as e:
        return 127, "", str(e)


def last_line(text):
    lines = [line for line in (text or "").splitlines() if line.strip()]
    return lines[-1] if lines else ""


def command(name):
    """A Butler command's program from the manifest, or None when the command is not installed."""
    return CONFIG.get("commands", {}).get(name)


def jwt_exp(token):
    try:
        payload = token.split(".")[1]
        return int(json.loads(base64.urlsafe_b64decode(payload + "=" * (-len(payload) % 4)))["exp"])
    except (IndexError, ValueError, KeyError, TypeError):
        return None


def read_json(path, default=None):
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def age(seconds):
    seconds = max(0, int(seconds))
    if seconds < 3600:
        return "%d minutes" % (seconds // 60)
    if seconds < 2 * DAY:
        return "%d hours" % (seconds // 3600)
    return "%d days" % (seconds // DAY)


def nonempty(path):
    try:
        return os.path.getsize(path) > 0
    except OSError:
        return False


def to_epoch(value):
    """An ISO time or a number of seconds or milliseconds, as epoch seconds, or None."""
    stamp = iso_epoch(value)
    if stamp is not None:
        return stamp
    try:
        number = float(value)
    except (TypeError, ValueError):
        return None
    return number / 1000 if number > 1e11 else number


def iso_epoch(text):
    try:
        return datetime.datetime.fromisoformat(str(text).replace("Z", "+00:00")).timestamp()
    except (ValueError, TypeError):
        return None


def unit_state(unit):
    code, out, _ = run([CONFIG.get("systemctl", "systemctl"), "show", unit, "-p", "ActiveState,Result,LoadState,ExecMainExitTimestamp"], timeout=15)
    return dict(line.split("=", 1) for line in out.splitlines() if "=" in line) if code == 0 else {}


def expiring(expires, now, what, fix):
    if expires and expires - now < EXPIRY_DAYS * DAY:
        if expires <= now:
            return fail("%s expired %s ago" % (what, age(now - expires)), fix)
        return warn("%s expires in %s" % (what, age(expires - now)), fix, expires)
    return None


def check(id, name, group):
    def wrap(f):
        CHECKS[id] = {"id": id, "name": name, "group": group, "run": f}
        return f
    return wrap


def enabled(name):
    return CONFIG.get("enabled", {}).get(name, True)


# ---------------------------------------------------------------- mail

def himalaya(account):
    return run([CONFIG["himalaya"], "--config", CONFIG["himalayaConfig"], "--log-level", "off", "--json", "--account", account, "envelope", "list", "--page-size", "1"], timeout=45)


def mail_check(account):
    spec = CONFIG.get("mail", {}).get(account)
    if spec is None:
        return result("off", "no %s account in butler.mail.accounts" % account)
    if spec.get("credential") and not credential(spec["credential"]):
        return unconnected("no app password written yet", spec["fix"])
    if spec.get("tokenFile") and not nonempty(spec["tokenFile"]):
        return unconnected("not logged in yet", spec["fix"])
    code, out, err = himalaya(account)
    if code == 0:
        return ok("listed the inbox over IMAP")
    return fail("IMAP read failed: %s" % (last_line(err) or last_line(out) or "exit %d" % code), spec["fix"])


@check("mail-fastmail", "Fastmail mail", "mail")
def _(now):
    return mail_check("fastmail")


@check("mail-gmail", "Gmail mail", "mail")
def _(now):
    return mail_check("gmail")


@check("mail-outlook", "Outlook mail", "mail")
def _(now):
    return mail_check("outlook")


def work_google(args):
    exe = CONFIG.get("workGoogle")
    if not exe:
        return result("off", "the work Google reader is not enabled")
    code, out, err = run([exe] + args, timeout=40)
    fix = CONFIG.get("workGoogleFix", "")
    if code == 0:
        return ok("read the work account")
    if code == 78:
        return unconnected(last_line(err), fix)
    if code == 77:
        return fail("the work workspace's admin blocks the app: " + last_line(err), "ask the work workspace's admin to trust the client ID")
    if code == 75 and "refused" in err:
        return fail(last_line(err), fix)
    return fail(last_line(err) or "exit %d" % code, fix)


@check("work-mail", "Work Google mail (read-only)", "mail")
def _(now):
    return work_google(["mail", "unread-count"])


@check("work-calendar", "Work Google calendar (read-only)", "calendar")
def _(now):
    return work_google(["calendar", "agenda"])


@check("inbox-monitor", "Inbox monitor", "mail")
def _(now):
    if not enabled("inbox"):
        return result("off", "butler.inbox is off")
    status = read_json(CONFIG["inboxStatus"])
    if status is None:
        return fail("the inbox monitor has written no status", "sudo systemctl restart butler-inbox")
    state = ""
    try:
        with open(CONFIG["inboxState"]) as f:
            state = f.read().strip()
    except OSError:
        pass
    if state == "off":
        return warn("switched off with /inbox off", "/inbox on in Butler's DM")
    updated = iso_epoch(status.get("updatedAt")) or 0
    if now - updated > 15 * 60:
        return fail("no poll for %s" % age(now - updated), "sudo systemctl restart butler-inbox")
    bad = ["%s: %s" % (f.get("name"), f.get("lastError")) for f in status.get("feeds", []) if f.get("lastError")]
    if bad:
        return warn("; ".join(bad), "check the mail account named; the account's own mail check says more")
    return ok("polled %s ago" % age(now - updated))


# ---------------------------------------------------------------- Home Assistant and calendar

def ha(path):
    token = credential("home-assistant-token")
    if not token:
        return None, None
    status, _, body = http("GET", CONFIG["homeAssistant"] + path, {"Authorization": "Bearer " + token}, timeout=15)
    return status, body


HA_FIX = "make a new long-lived token for \"Butler on spike\" in Home Assistant, write it to /var/lib/secrets/butler-home-assistant-token, then systemctl restart butler"


@check("home-assistant", "Home Assistant", "home")
def _(now):
    token = credential("home-assistant-token")
    if not token:
        return unconnected("no Home Assistant token written yet", HA_FIX)
    status, body = ha("/api/")
    if status == 200:
        return expiring(jwt_exp(token), now, "the Home Assistant token", HA_FIX) or ok("API running", expires=jwt_exp(token))
    if status in (401, 403):
        return fail("Home Assistant refused butler's token (HTTP %d)" % status, HA_FIX)
    return fail("Home Assistant answered HTTP %s: %s" % (status, body[:80].decode(errors="replace")), "sudo systemctl restart home-assistant")


@check("google-calendar", "Google Calendar through Home Assistant", "calendar")
def _(now):
    if not credential("home-assistant-token"):
        return unconnected("no Home Assistant token written yet", HA_FIX)
    status, body = ha("/api/calendars")
    calendars = jbody(body) if status == 200 else None
    if not isinstance(calendars, list):
        return fail("Home Assistant's calendar list answered HTTP %s" % status, HA_FIX if status in (401, 403) else "check Home Assistant's Google Calendar integration")
    if not calendars:
        return fail("Home Assistant has no calendars", "reconfigure the Google Calendar integration in Home Assistant")
    down = []
    for c in calendars:
        status, body = ha("/api/states/" + urllib.parse.quote(c.get("entity_id", "")))
        if status != 200:
            return warn("Home Assistant did not answer for %s (HTTP %s), so the calendars are unjudged" % (c.get("entity_id"), status), "")
        if (jbody(body) or {}).get("state") == "unavailable":
            down.append(c["entity_id"])
    if len(down) == len(calendars):
        return fail("every calendar is unavailable, so Google's login has likely lapsed", "reauthenticate Google Calendar in Home Assistant's integrations page")
    if down:
        return warn("%d of %d calendars unavailable" % (len(down), len(calendars)), "reauthenticate Google Calendar in Home Assistant's integrations page")
    return ok("%d calendars readable" % len(calendars))


# ---------------------------------------------------------------- iCloud

ICLOUD_FIX = "sudo -u butler butler-icloud-login <apple-id>"


ICLOUD_LOCK = threading.Lock()


def icloud(name, args):
    exe = command(name)
    if not exe:
        return result("off", "the %s command is not installed" % name)
    if not os.path.exists(CONFIG["icloudAppleId"]):
        return unconnected("not logged in to iCloud yet", ICLOUD_FIX)
    # Reminders and Photos share one pyicloud session, which each may rewrite, so they never run at once.
    with ICLOUD_LOCK:
        code, out, err = run([exe] + args, timeout=50)
    if code == 0:
        return ok("read through the iCloud session")
    if code == 75 and "expired" in err:
        return fail("the iCloud session expired", ICLOUD_FIX)
    return fail(last_line(err) or "exit %d" % code, ICLOUD_FIX)


@check("icloud-reminders", "Apple Reminders", "icloud")
def _(now):
    return icloud("reminders", ["lists"])


@check("icloud-photos", "iCloud Photos", "icloud")
def _(now):
    return icloud("photos", ["albums"])


# ---------------------------------------------------------------- money and health

@check("up", "Up bank", "money")
def _(now):
    token = credential("up-token")
    fix = "make a new personal access token in the Up app, write it to /var/lib/secrets/butler-index-up-token, then systemctl restart butler"
    if not token:
        return unconnected("no Up token written yet", fix)
    status, _, body = http("GET", "https://api.up.com.au/api/v1/util/ping", {"Authorization": "Bearer " + token, "Accept": "application/json"})
    if status == 200:
        return ok("ping answered")
    if status == 401:
        return fail("Up refused the token (HTTP 401)", fix)
    return fail("Up answered HTTP %s" % (status or body[:80].decode(errors="replace")), fix)


GARMIN = "https://personal.connectapi.garmin.com"


@check("garmin", "Garmin Connect", "health")
def _(now):
    if not enabled("garmin"):
        return result("off", "butler.garmin is off")
    key = credential("garmin-api-key")
    fix = "make a new Personal API key in Garmin Connect's web settings and write it to /var/lib/secrets/butler-garmin-api-key, then systemctl restart butler"
    if not key:
        return unconnected("no Garmin API key written yet", fix)
    # The JWT the command cached, when it still has an hour; otherwise one traded for the key and thrown away.
    token = ""
    try:
        with open(CONFIG["garminToken"]) as f:
            token = f.read().strip()
    except OSError:
        pass
    if not token or (jwt_exp(token) or 0) - now < 3600:
        status, _, body = http("POST", GARMIN + "/personalapitoken-service/personal-api/personal-api-key/token", {"Authorization": "ApiKey " + key, "Accept": "*/*"}, data=b"")
        if not 200 <= status < 300:
            return fail("Garmin refused the API key (HTTP %s)" % status, fix)
        token = body.decode().strip().strip('"')
    status, _, _ = http("GET", GARMIN + "/userprofile-service/userprofile/settings", {"Authorization": "Bearer " + token, "Accept": "application/json"})
    if 200 <= status < 300:
        return ok("read the profile settings")
    return fail("Garmin answered HTTP %s for the profile" % status, fix)


@check("hevy", "Hevy", "health")
def _(now):
    if not enabled("hevy"):
        return result("off", "butler.hevy is off")
    exe = command("hevy")
    fix = "sudo -u butler hevy login"
    if not os.path.exists(CONFIG["hevySession"]):
        return unconnected("not logged in to Hevy yet", fix)
    code, out, err = run([exe, "folders"], timeout=40)
    if code == 0:
        return ok("listed the routine folders")
    if code == 75:
        return fail("the Hevy session is missing or was refused", fix)
    return fail(last_line(err) or "exit %d" % code, fix)


# ---------------------------------------------------------------- live feeds

def feed(name, now):
    status = read_json(CONFIG["feedsStatus"], {}) or {}
    entry = status.get(name)
    fix = "sudo butler-feeds-login %s" % name
    if not entry:
        return unconnected("the feed has not run yet", fix if name in ("spotify", "steam", "paypal", "letterboxd", "goodreads") else "")
    checked = iso_epoch(entry.get("checked")) or 0
    message = entry.get("message") or ""
    if entry.get("state") == "needs-login":
        return unconnected(message or "waiting on a login", fix)
    if entry.get("state") == "failing":
        return fail(message or "failing", fix if "401" in message or "403" in message or "refused" in message.lower() else "journalctl -u butler-feeds")
    if now - checked > 4 * 3600:
        return warn("the hourly feed last ran %s ago" % age(now - checked), "journalctl -u butler-feeds")
    return ok("connected, checked %s ago" % age(now - checked))


@check("feed-spotify", "Spotify feed", "feeds")
def _(now):
    return feed("spotify", now)


@check("feed-steam", "Steam feed", "feeds")
def _(now):
    return feed("steam", now)


@check("feed-paypal", "PayPal feed", "feeds")
def _(now):
    return feed("paypal", now)


@check("feed-letterboxd", "Letterboxd feed", "feeds")
def _(now):
    return feed("letterboxd", now)


@check("feed-goodreads", "Goodreads feed", "feeds")
def _(now):
    return feed("goodreads", now)


@check("feed-mail", "Statements and receipts from mail", "feeds")
def _(now):
    return feed("mail", now)


# ---------------------------------------------------------------- Slack and Messenger

def slack_scopes(token):
    status, headers, body = http("GET", "https://slack.com/api/auth.test", {"Authorization": "Bearer " + token})
    data = jbody(body) or {}
    scopes = {s.strip() for s in headers.get("x-oauth-scopes", "").split(",") if s.strip()}
    return status, data, scopes


@check("slack-read", "Slack (reading)", "messaging")
def _(now):
    token = credential("slack-token")
    fix = "sudo butler-slack-login"
    if not token:
        return unconnected("no Slack token written yet", fix)
    status, data, scopes = slack_scopes(token)
    if status == 429:
        return warn("Slack rate limited auth.test", "")
    if not data.get("ok"):
        return fail("Slack refused the token: %s" % (data.get("error") or "HTTP %s" % status), fix)
    missing = [s for s in CONFIG["slackRead"] if s not in scopes]
    if missing:
        return fail("the token lost scopes: %s" % ", ".join(missing), fix)
    writes = [s for s in CONFIG["slackWrite"] if s in scopes]
    if writes:
        return warn("the reading token can write (%s)" % ", ".join(writes), fix)
    return ok("auth.test passed with every read scope")


@check("slack-write", "Slack (sending, gated)", "messaging")
def _(now):
    token = credential("slack-write-token")
    fix = "sudo butler-slack-login --write"
    if not token:
        return unconnected("no Slack writing token written yet", fix)
    # auth.test alone: it reads who the token is and its scopes, and never posts.
    status, data, scopes = slack_scopes(token)
    if status == 429:
        return warn("Slack rate limited auth.test", "")
    if not data.get("ok"):
        return fail("Slack refused the writing token: %s" % (data.get("error") or "HTTP %s" % status), fix)
    missing = [s for s in CONFIG["slackWrite"] + CONFIG["slackWriteLookup"] if s not in scopes]
    if missing:
        return fail("the writing token lost scopes: %s" % ", ".join(missing), fix)
    return ok("auth.test passed with every write scope; nothing was posted")


def matrix(path, token):
    return http("GET", CONFIG["matrix"] + path, {"Authorization": "Bearer " + token}, timeout=15)


@check("messenger", "Messenger and Marketplace", "messaging")
def _(now):
    if not enabled("messenger"):
        return result("off", "butler.messenger is off")
    token = credential("matrix-token")
    fix = "sudo messenger-setup"
    if not token:
        return unconnected("no Matrix login made yet", fix)
    status, _, _ = matrix("/_matrix/client/v3/account/whoami", token)
    if status == 401:
        return fail("the homeserver refused butler's Matrix token", fix)
    if status != 200:
        return fail("the homeserver answered HTTP %s" % status, "sudo systemctl restart tuwunel")
    status, _, body = matrix("/_matrix/client/v3/joined_rooms", token)
    rooms = (jbody(body) or {}).get("joined_rooms", [])
    if not rooms:
        return fail("no bridged chats, so the bridge never logged in", fix)
    # The bridge's Facebook login cannot be read without writing to its bot, so the newest message stands in for it.
    newest = chat_newest("messenger")
    if newest and now - newest > 3 * DAY:
        return warn("%d chats, but nothing new from Messenger in %s; its Facebook login has probably lapsed" % (len(rooms), age(now - newest)), fix)
    return ok("%d chats listed" % len(rooms))


def chat_db():
    path = CONFIG["chatDb"]
    if not os.path.exists(path):
        return None
    return sqlite3.connect("file:%s?mode=ro" % urllib.parse.quote(path), uri=True, timeout=5)


def chat_newest(source):
    try:
        db = chat_db()
        if db is None:
            return None
        row = db.execute("SELECT max(last_ts) FROM conversations WHERE source = ? AND NOT last_from_me", (source,)).fetchone()
        return to_epoch(row[0]) if row else None
    except sqlite3.Error:
        return None


@check("chat-cache", "Chat cache (Discord, Google Chat and the rest)", "messaging")
def _(now):
    fix = "chat refresh, or journalctl -u butler-chat-sync"
    try:
        db = chat_db()
        if db is None:
            return fail("the chat cache is not built yet", fix)
        meta = dict(db.execute("SELECT key, value FROM meta").fetchall())
    except sqlite3.Error as e:
        return fail("the chat cache cannot be read: %s" % e, fix)
    synced = to_epoch(meta.get("synced"))
    ingested = {k.split(":", 1)[1]: v for k, v in meta.items() if k.startswith("ingested:")}
    detail = {source: value for source, value in sorted(ingested.items())}
    if not synced or now - synced > 2 * 3600:
        return fail("the chat cache was last built %s ago" % (age(now - synced) if synced else "never"), fix)
    return ok("built %s ago; index ingests: %s" % (age(now - synced), ", ".join("%s %s" % (k, str(v)[:10]) for k, v in detail.items()) or "none"), detail=detail)


# ---------------------------------------------------------------- notes, reMarkable, Drive

@check("notes", "Obsidian notes sync", "notes")
def _(now):
    config = CONFIG["notesConfig"]
    fix = "sudo -u butler butler-notes-login Latte, then sudo systemctl start butler-notes-sync"
    try:
        logged_in = bool(os.listdir(config))
    except OSError:
        logged_in = False
    if not logged_in:
        return unconnected("Obsidian Sync is not logged in yet", fix)
    unit = unit_state("butler-notes-sync.service")
    if unit.get("Result") not in (None, "success"):
        return fail("the last sync ended with %s" % unit.get("Result"), "journalctl -u butler-notes-sync; if it says the login is gone, " + fix)
    newest = 0
    for root, dirs, files in os.walk(CONFIG["notesVault"]):
        dirs[:] = [d for d in dirs if not d.startswith(".")]
        for name in files:
            try:
                newest = max(newest, os.path.getmtime(os.path.join(root, name)))
            except OSError:
                pass
    stamp = unit.get("ExecMainExitTimestamp", "")
    return ok("the 15-minute sync succeeds; newest note changed %s ago" % age(now - newest) if newest else "the sync succeeds", detail={"lastSync": stamp})


@check("remarkable", "reMarkable cloud", "notes")
def _(now):
    if not enabled("remarkable"):
        return result("off", "butler.remarkable is off")
    status = read_json(CONFIG["remarkableStatus"])
    fix = "sudo butler-remarkable-login"
    if status is None or (not status.get("loggedIn") and status.get("error") in (None, "not logged in")):
        return unconnected("not logged in to reMarkable yet", fix)
    if not status.get("loggedIn"):
        return fail("reMarkable refused the device token: %s" % (status.get("error") or ""), fix)
    last = iso_epoch(status.get("lastSync")) or 0
    if status.get("error"):
        return fail("the last sync failed: %s" % status["error"], "journalctl -u butler-remarkable-sync")
    if now - last > 4 * 3600:
        return warn("the hourly sync last finished %s ago" % age(now - last), "journalctl -u butler-remarkable-sync")
    return ok("synced %s ago" % age(now - last))


@check("drive", "Google Drive", "notes")
def _(now):
    if not enabled("drive"):
        return result("off", "butler.drive is off")
    fix = "sudo -u butler butler-drive-login, over ssh forwarding port 53682"
    if not os.path.exists(CONFIG["rcloneConfig"]):
        return unconnected("not logged in to Drive yet", fix)
    code, out, err = run([command("drive"), "ls"], timeout=45)
    if code == 0:
        return ok("listed My Drive")
    return fail(last_line(err) or "exit %d" % code, fix)


# ---------------------------------------------------------------- places and weather

@check("maps", "Google Maps", "places")
def _(now):
    key = credential("google-maps-api-key")
    fix = "write a Google Maps Platform key to /var/lib/secrets/butler-google-maps-api-key, then systemctl restart butler"
    if not key:
        return unconnected("no Google Maps key written yet", fix)
    # Text Search asking only for place IDs is Google's free IDs Only SKU, so this check costs nothing.
    status, _, body = http("POST", "https://places.googleapis.com/v1/places:searchText",
                           {"X-Goog-Api-Key": key, "X-Goog-FieldMask": "places.id", "Content-Type": "application/json"},
                           data={"textQuery": "Collingwood VIC", "pageSize": 1})
    usage = read_json(CONFIG["mapsUsage"], {}) or {}
    limits = CONFIG["mapsLimits"]
    if status in (400, 403):
        error = (jbody(body) or {}).get("error", {}).get("message", "HTTP %d" % status)
        return fail("Google refused the key: %s" % error, fix)
    if status != 200:
        return fail("Places answered HTTP %s" % status, fix)
    if usage.get("month") == time.strftime("%Y-%m"):
        for kind, limit in limits.items():
            if usage.get(kind, 0) >= 0.8 * limit:
                return warn("%s calls this month are %d of the free %d" % (kind, usage.get(kind, 0), limit), "")
    return ok("the key works; this month %s" % ", ".join("%s %d" % (k, usage.get(k, 0)) for k in limits))


@check("weather", "Open-Meteo weather", "places")
def _(now):
    status, _, body = http("GET", "https://api.open-meteo.com/v1/forecast?latitude=-37.8031&longitude=144.9873&current=temperature_2m")
    if status == 200 and "current" in (jbody(body) or {}):
        return ok("forecast answered")
    return fail("Open-Meteo answered HTTP %s" % status, "")


@check("mindbody", "REVL's Mindbody timetable", "places")
def _(now):
    status, _, body = http("GET", CONFIG["mindbodyUrl"], {"Accept": "text/html"})
    if status != 200:
        return fail("the schedule widget answered HTTP %s" % status, "")
    if b"self.__next_f.push" not in body:
        return fail("the schedule page changed shape, so mindbody cannot parse it", "a change to butler-mindbody/mindbody.py")
    return ok("timetable page parses")


# ---------------------------------------------------------------- GitHub

def prom_file(path):
    values = []
    try:
        with open(path) as f:
            for line in f:
                m = re.match(r'^([a-zA-Z_:]+)(\{[^}]*\})?\s+(\S+)', line)
                if m:
                    labels = dict(re.findall(r'(\w+)="([^"]*)"', m.group(2) or ""))
                    values.append((m.group(1), labels, float(m.group(3))))
    except (OSError, ValueError):
        return None
    return values


@check("github", "GitHub keys (aaron, butler-daemon, butler-memory)", "github")
def _(now):
    values = prom_file(CONFIG["monitorProm"])
    if values is None:
        return fail("the machines monitor has written no readings", "sudo systemctl start butler-monitor")
    last = next((v for n, _, v in values if n == "butler_monitor_last_run_timestamp_seconds"), 0)
    identities = {labels.get("identity"): v for n, labels, v in values if n == "butler_monitor_github_auth_ok"}
    if now - last > 30 * 60:
        return warn("the machines monitor last ran %s ago, so GitHub's keys are unchecked" % age(now - last), "sudo systemctl start butler-monitor")
    refused = sorted(name for name, v in identities.items() if not v)
    if refused:
        fixes = CONFIG.get("githubFix", {})
        return fail("GitHub refused %s" % ", ".join(refused), "; ".join("%s: re-add the key at %s" % (r, fixes.get(r, "GitHub")) for r in refused))
    return ok("%s authenticate" % ", ".join(sorted(identities)) if identities else "no identities read")


def github_token(name, fix):
    token = credential(name)
    if not token:
        return unconnected("no token written yet", fix)
    status, headers, _ = http("GET", "https://api.github.com/rate_limit", {"Authorization": "Bearer " + token, "Accept": "application/vnd.github+json"})
    if status == 401:
        return fail("GitHub refused the token (HTTP 401)", fix)
    if status != 200:
        return fail("GitHub answered HTTP %s" % status, fix)
    expires = None
    stamp = headers.get("github-authentication-token-expiration")
    if stamp:
        try:
            expires = datetime.datetime.strptime(stamp.replace(" UTC", " +0000"), "%Y-%m-%d %H:%M:%S %z").timestamp()
        except ValueError:
            expires = None
    return expiring(expires, time.time(), "the token", fix) or ok("the token works", expires=expires)


@check("github-issues-token", "GitHub issues token", "github")
def _(now):
    return github_token("github-issues-token", "make a new fine-grained token for kranners with issues read and write, write it to /var/lib/secrets/butler-github-issues-token, then systemctl restart butler")


@check("github-backlogic-token", "GitHub backlogic read token", "github")
def _(now):
    return github_token("github-backlogic-token", "make a new read-only fine-grained token owned by the backlogic organisation, write it to /var/lib/secrets/butler-github-backlogic-token, then systemctl restart butler")


# ---------------------------------------------------------------- backlogic and the board

@check("backlogic-instance", "backlogic instance API", "backlogic")
def _(now):
    token = credential("backlogic-token")
    fix = "mint an owner token in backlogic's settings, write it to /var/lib/secrets/butler-backlogic-token, then systemctl restart butler"
    if not token:
        return unconnected("no backlogic token written yet", fix)
    status, _, _ = http("GET", CONFIG["backlogic"] + "/api/snapshot", {"Authorization": "Bearer " + token}, timeout=20)
    if status == 200:
        return ok("snapshot read")
    if status in (401, 403):
        return fail("backlogic refused butler's token (HTTP %d)" % status, fix)
    return fail("backlogic answered HTTP %s" % status, "backlogic-compose ps; sudo systemctl restart backlogic-aaron")


@check("backlogic-runner", "backlogic runner", "backlogic")
def _(now):
    unit = unit_state("backlogic-runner-aaron.service")
    if unit.get("ActiveState") != "active":
        return fail("backlogic-runner-aaron is %s" % (unit.get("ActiveState") or "unknown"), "sudo systemctl restart backlogic-runner-aaron")
    gates = unit_state("backlogic-runner-gates.service")
    if gates.get("Result") not in (None, "success"):
        return fail("backlogic-runner-gates ended with %s" % gates.get("Result"), "journalctl -u backlogic-runner-gates")
    values = prom_file(CONFIG["sweepProm"]) or []
    last = next((v for n, _, v in values if n == "backlogic_sweep_last_run_seconds"), None)
    if last and now - last > 40 * 60:
        return warn("the runner runs, but the sweep last read it %s ago" % age(now - last), "journalctl -u backlogic-sweep")
    return ok("runner active and its gates applied")


@check("backlogic-tunnel", "backlogic public API tunnel", "backlogic")
def _(now):
    unit = unit_state("backlogic-tunnel.service")
    if unit.get("LoadState") == "not-found":
        return result("off", "no tunnel unit")
    if unit.get("ActiveState") != "active":
        return unconnected("the tunnel is not running; its token may not be written yet", "write the Cloudflare tunnel token to /var/lib/secrets/cloudflared-backlogic-token, then sudo systemctl start backlogic-tunnel")
    status, _, _ = http("GET", "https://backlogic-api.cute.engineer/api/snapshot", timeout=20)
    if status in (401, 403):
        return ok("the tunnel answers and still asks for a token")
    if status == 200:
        return fail("the public API answered without a token", "check backlogic-tunnel's Caddy site at once")
    return fail("the public API answered HTTP %s" % status, "journalctl -u backlogic-tunnel")


@check("backlogic-peer", "backlogic peer link to Rylee's instance", "backlogic")
def _(now):
    status, _, body = http("GET", CONFIG["backlogicPeer"], timeout=15)
    if status:
        return ok("Rylee's instance answers (HTTP %d)" % status)
    return warn("Rylee's instance does not answer: %s" % body[:80].decode(errors="replace"), "nothing on spike; her machine or its WireGuard is down")


@check("kanban", "Kanban board", "board")
def _(now):
    if os.path.exists(CONFIG["kanbanMarker"]):
        status, _, _ = http("GET", "http://127.0.0.1:7420/healthz", timeout=10)
        if status == 200:
            return ok("the board on spike answers")
        return fail("the board on spike answered HTTP %s" % status, "sudo systemctl restart kanban; sudo kanban-recovery-check")
    unit = unit_state("kanban-tunnel.service")
    if unit.get("LoadState") == "not-found":
        return result("off", "the board is not served")
    return warn("the board still lives on pilot, so it is not checked from here", "sudo kanban-hub cutover --yes, when Aaron chooses")


# ---------------------------------------------------------------- OpenAI and Claude

def openai_key(*names):
    for name in names:
        key = credential(name)
        if key:
            return name, key
    return None, ""


IMAGINE_FIX = "write an OpenAI key to /var/lib/secrets/butler-openai-api-key, then systemctl restart butler"


@check("openai-image", "OpenAI images key", "openai")
def _(now):
    _, key = openai_key("openai-api-key")
    if not key:
        return unconnected("no OpenAI key written yet", IMAGINE_FIX)
    # Listing models is free; nothing is generated.
    status, _, body = http("GET", "https://api.openai.com/v1/models", {"Authorization": "Bearer " + key})
    if status == 200:
        return ok("the key authenticates")
    if status == 403:
        return warn("the key authenticates but may not list models (HTTP 403)", "")
    if status == 401:
        return fail("OpenAI refused the key (HTTP 401)", IMAGINE_FIX)
    return fail("OpenAI answered HTTP %s" % status, IMAGINE_FIX)


@check("openai-voice", "OpenAI realtime voice key", "openai")
def _(now):
    name, key = openai_key("openai-audio-key", "openai-api-key")
    if not key:
        return unconnected("no OpenAI key written yet", IMAGINE_FIX)
    # An ephemeral realtime client secret costs nothing and is thrown away.
    status, _, body = http("POST", "https://api.openai.com/v1/realtime/client_secrets", {"Authorization": "Bearer " + key, "Content-Type": "application/json"},
                           data={"session": {"type": "realtime", "model": CONFIG["realtimeModel"]}})
    which = "the dedicated audio key" if name == "openai-audio-key" else "the shared images key"
    if status == 200:
        return ok("%s may open realtime sessions" % which)
    error = ((jbody(body) or {}).get("error") or {}).get("message", "HTTP %s" % status)
    if status in (401, 403):
        return fail("OpenAI refused %s for realtime: %s" % (which, error), "switch on the key's Realtime permission in OpenAI's dashboard, or write a dedicated key to /var/lib/secrets/butler-openai-audio-key")
    return fail("OpenAI answered %s: %s" % (status, error), "")


@check("claude-accounts", "Claude accounts", "claude")
def _(now):
    problems, warnings, seen = [], [], []
    for path in sorted(CONFIG.get("claudeLimits", [])):
        account = os.path.basename(path)[len("claude-limits-"):-len(".prom")]
        values = prom_file(path)
        if values is None:
            problems.append("%s has no usage reading" % account)
            continue
        seen.append(account)
        mtime = os.path.getmtime(path)
        weekly = max((v for n, labels, v in values if n == "claude_limit_percent" and labels.get("kind") == "weekly_all"), default=None)
        if now - mtime > 2 * 3600:
            warnings.append("%s's usage reading is %s old, so its login may be refused" % (account, age(now - mtime)))
        if weekly is not None and weekly >= 90:
            warnings.append("%s is at %.0f%% of its week" % (account, weekly))
    # Butler's own account tokens: butler-claude writes a refused account's cooldown as an hour from when it asked,
    # and a limited one's as its reset time, so a cooldown an hour past its file's time is a refusal.
    refused = []
    try:
        for name in sorted(os.listdir(CONFIG["butlerCooldowns"])):
            path = os.path.join(CONFIG["butlerCooldowns"], name)
            with open(path) as f:
                until = int(f.read().strip() or 0)
            if until > now and 3570 <= until - os.path.getmtime(path) <= 3601:
                refused.append(name)
    except (OSError, ValueError):
        pass
    tokens = 0
    try:
        with open(CONFIG["butlerAccounts"]) as f:
            tokens = sum(1 for line in f if line.strip())
    except OSError:
        pass
    if refused:
        problems.append("Anthropic refused Butler's account %s in the last hour" % ", ".join(refused))
    fix = "make a new token with claude setup-token and replace that account's line in /var/lib/butler/.claude-accounts/tokens"
    if problems:
        return fail("; ".join(problems + warnings), fix)
    if warnings:
        return warn("; ".join(warnings), "the runner's logins: CLAUDE_CONFIG_DIR=<dir> claude auth login as backlogic-runner")
    return ok("%s readable; Butler has %d account tokens and none refused" % (", ".join(seen) or "no accounts", tokens))


# ---------------------------------------------------------------- the index

@check("index-freshness", "Personal data index", "index")
def _(now):
    exe = command("life")
    if not exe:
        return result("off", "the life command is not installed")
    code, out, err = run([exe, "sources"], timeout=50)
    data = jbody(out) if code == 0 else None
    if not isinstance(data, dict):
        return fail("life sources failed: %s" % (last_line(err) or "exit %d" % code), "journalctl -u butler-index-ingest")
    sources = data.get("sources", [])
    by_name = {s.get("source"): s for s in sources}
    continuous = []
    catalogue = read_json(CONFIG["dataSources"], {}) or {}
    for entry in catalogue.get("sources", []):
        if entry.get("group") == "continuous":
            continuous += entry.get("index") or []
    stale = []
    for name in sorted(set(continuous)):
        s = by_name.get(name)
        stamp = to_epoch((s or {}).get("last_ingest")) if s else None
        if stamp and now - stamp > 2 * DAY:
            stale.append("%s %s" % (name, age(now - stamp)))
    detail = {s.get("source"): s.get("last_ingest") for s in sources}
    if stale:
        return warn("continuous sources not ingested lately: %s" % ", ".join(stale), "journalctl -u butler-index-ingest, and that source's own check here")
    return ok("%d sources, every continuous one ingested in the last 2 days" % len(sources), detail=detail)


@check("exports-waiting", "Exports waiting in the index inbox", "index")
def _(now):
    """A password-protected zip the ingest cannot open until Aaron unlocks it, and the ingest's own last run."""
    inbox = CONFIG["indexInbox"]
    locked = []
    try:
        folders = sorted(os.listdir(inbox))
    except OSError:
        return fail("the index inbox cannot be read", "")
    for folder in folders:
        directory = os.path.join(inbox, folder)
        if folder.startswith(".") or folder in CONFIG["inboxSkip"] or not os.path.isdir(directory):
            continue
        for name in sorted(os.listdir(directory)):
            if not name.lower().endswith(".zip"):
                continue
            try:
                with zipfile.ZipFile(os.path.join(directory, name)) as archive:
                    if any(info.flag_bits & 1 for info in archive.infolist()):
                        locked.append("%s/%s" % (folder, name))
            except (OSError, zipfile.BadZipFile, ValueError):
                continue
    if locked:
        return warn("%d password-protected exports wait to be unlocked: %s" % (len(locked), ", ".join(locked[:5])), "sudo butler-index-unlock <folder> <zip>, with its password in /var/lib/secrets/butler-index-zip-password")
    unit = unit_state("butler-index-ingest.service")
    if unit.get("Result") not in (None, "success"):
        return warn("the index's last ingest ended with %s" % unit.get("Result"), "journalctl -u butler-index-ingest")
    return ok("nothing locked, and the last ingest succeeded")


# ---------------------------------------------------------------- machines, certificates, disk

@check("machines", "Macs and the PC (ssh, pilot read-only)", "machines")
def _(now):
    snapshot = read_json(CONFIG["machines"])
    if not snapshot:
        return fail("the machines monitor has written no snapshot", "sudo systemctl start butler-monitor")
    if now - snapshot.get("generated", 0) > 30 * 60:
        return warn("the machines monitor last ran %s ago" % age(now - snapshot.get("generated", 0)), "sudo systemctl start butler-monitor")
    down = [m["host"] for m in snapshot.get("machines", []) if m.get("up") is False and not m.get("expected")]
    if down:
        return warn("not reachable over ssh: %s" % ", ".join(down), "wake it or check its WireGuard; mac hosts says more")
    return ok("every machine the monitor reads answers or is expected off")


def certificate(site):
    context = ssl.create_default_context()
    with socket.create_connection((CONFIG["caddyAddress"], 443), timeout=10) as raw:
        with context.wrap_socket(raw, server_hostname=site) as tls:
            return ssl.cert_time_to_seconds(tls.getpeercert()["notAfter"])


@check("certificates", "HTTPS certificates of spike's sites", "machines")
def _(now):
    bad, soon, ends = [], [], {}
    for site in CONFIG["sites"]:
        try:
            ends[site] = certificate(site)
        except (OSError, ssl.SSLError, KeyError, ValueError) as e:
            bad.append("%s: %s" % (site, redact(str(e))[:80]))
            continue
        if ends[site] - now < EXPIRY_DAYS * DAY:
            soon.append("%s in %s" % (site, age(ends[site] - now)))
    fix = "journalctl -u caddy; Caddy renews 30 days ahead through Cloudflare's DNS token in /var/lib/secrets/cloudflare-dyndns-token"
    if bad:
        return fail("; ".join(bad), fix)
    first = min(ends.values()) if ends else None
    if soon:
        return warn("certificates expire soon: %s" % ", ".join(soon), fix, first)
    return ok("%d sites, the soonest expiring in %s" % (len(ends), age(first - now) if first else "?"), expires=first)


@check("disk", "Disk and Nix store", "machines")
def _(now):
    st = os.statvfs("/")
    free = st.f_bavail / st.f_blocks if st.f_blocks else 1
    inodes = st.f_favail / st.f_files if st.f_files else 1
    text = "%.0f GB free (%.0f%%), %.0f%% of inodes free" % (st.f_bavail * st.f_frsize / 1e9, free * 100, inodes * 100)
    fix = "sudo nix-collect-garbage, after prune-generations; the monitor's diskFull remediation does the same"
    if free < 0.08 or inodes < 0.1:
        return fail(text, fix)
    if free < 0.15 or inodes < 0.2:
        return warn(text, fix)
    return ok(text)


# ---------------------------------------------------------------- the writers' gates

def matches(match, call):
    """Whether a rule's match takes this call, as the daemon reads it: a word equal, `*` one argument, a trailing `**` the rest."""
    if match and match[-1] == "**":
        head = match[:-1]
        return len(call) >= len(head) and all(m in (c, "*") for m, c in zip(head, call))
    return len(match) == len(call) and all(m in (c, "*") for m, c in zip(match, call))


def gate_problems(manifest, writes):
    """Each writer must exist and every rule for its writing verbs must stand behind Aaron's approval in the daemon:
    a send names the message outcome and taints, any other write is an `acts` rule. Nothing is run."""
    commands = {c["name"]: c for c in manifest.get("commands", [])}
    problems = []
    for spec in writes:
        c = commands.get(spec["command"])
        if c is None:
            if spec.get("optional"):
                continue
            problems.append("%s is missing from the manifest" % spec["command"])
            continue
        if not os.access(c.get("path", ""), os.X_OK):
            problems.append("%s's program is missing" % spec["command"])
        rules = []
        for call in spec["calls"]:
            found = [r for r in c.get("rules", []) if matches(r.get("match") or [], call)]
            if not found:
                problems.append("%s has no rule for %s" % (spec["command"], " ".join(call)))
            rules += [r for r in found if r not in rules]
        for r in rules:
            name = "%s %s" % (spec["command"], " ".join(r.get("match", [])[:2]))
            if spec["kind"] == "send":
                if (r.get("outcome") or {}).get("kind") != "message" or not r.get("taints") or not r.get("egress"):
                    problems.append("%s is not gated as a message to a person" % name)
            elif not r.get("acts"):
                problems.append("%s is not an acts rule" % name)
            if "voice" in r.get("lanes", []) and spec["kind"] == "send":
                problems.append("%s reaches the voice lane" % name)
    return problems


@check("write-gates", "Writers' approval gates (never run)", "gates")
def _(now):
    manifest = read_json(CONFIG["manifest"])
    if manifest is None:
        return fail("the command manifest cannot be read", "")
    problems = gate_problems(manifest, CONFIG["writes"])
    if problems:
        return fail("; ".join(problems), "a change to the command's rules in jimbo")
    return ok("%d writers each wait on Aaron's approval" % len(CONFIG["writes"]))


# ---------------------------------------------------------------- running, judging, telling

def run_one(spec, now, timeout):
    started = time.time()
    try:
        r = spec["run"](now)
    except Exception as e:  # noqa: BLE001 - one broken check never stops the rest
        r = fail("the check itself broke: %s: %s" % (type(e).__name__, e), "")
    r = {**r, "id": spec["id"], "name": spec["name"], "group": spec["group"], "ms": int((time.time() - started) * 1000)}
    if time.time() - started > timeout:
        r["cause"] = (r["cause"] + " (slow)").strip()
    return r


def run_all(ids=None, now=None, timeout=60):
    now = now or time.time()
    specs = [CHECKS[i] for i in (ids or CHECKS)]
    results = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        futures = {pool.submit(run_one, s, now, timeout): s for s in specs}
        for future in concurrent.futures.as_completed(futures):
            s = futures[future]
            try:
                results.append(future.result(timeout=timeout + 30))
            except concurrent.futures.TimeoutError:
                results.append({**fail("timed out", ""), "id": s["id"], "name": s["name"], "group": s["group"], "ms": timeout * 1000})
    order = list(CHECKS)
    return sorted(results, key=lambda r: order.index(r["id"]))


def summary(results):
    counts = {s: 0 for s in STATUSES}
    for r in results:
        counts[r["status"]] = counts.get(r["status"], 0) + 1
    return counts


def choose_alerts(results, state, now):
    """What to tell Aaron: checks failing now that were not failing last run, and credentials expiring within 14 days
    not told for that expiry already. A not-connected source and a known open failure are never told."""
    failing_before = set(state.get("failing", []))
    told = dict(state.get("expiryTold", {}))
    new = [r for r in results if r["status"] == "fail" and r["id"] not in failing_before]
    soon = [r for r in results if r.get("expires") and r["status"] in ("pass", "warn") and r["expires"] - now < EXPIRY_DAYS * DAY and told.get(r["id"]) != int(r["expires"])]
    state = {
        "failing": sorted(r["id"] for r in results if r["status"] == "fail"),
        "expiryTold": {r["id"]: told.get(r["id"], int(r["expires"])) for r in results if r.get("expires") and r["expires"] - now < EXPIRY_DAYS * DAY},
    }
    for r in soon:
        state["expiryTold"][r["id"]] = int(r["expires"])
    return new, soon, state


def alert_text(new, soon):
    if not new and not soon:
        return ""
    lines = []
    if new:
        lines.append("Integration check: %d newly failing." % len(new))
        lines += ["- %s: %s%s" % (r["name"], r["cause"], (" Fix: " + r["fix"]) if r["fix"] else "") for r in new]
    if soon:
        lines.append("Expiring within %d days:" % EXPIRY_DAYS)
        lines += ["- %s: %s%s" % (r["name"], r["cause"], (" Fix: " + r["fix"]) if r["fix"] else "") for r in soon]
    return redact_lines("\n".join(lines))[:1800]


def redact_lines(text):
    return "\n".join(redact(line) if not line.startswith("- ") else "- " + redact(line[2:]) for line in text.splitlines())


def status_document(results, now, coverage):
    return {
        "version": 1,
        "generated": int(now),
        "summary": summary(results),
        "checks": [{k: r.get(k) for k in ("id", "name", "group", "status", "cause", "fix", "expires", "ms")} for r in results],
        "noLiveCheck": sorted(({"command": c, "reason": v[len("none: "):]} for c, v in coverage.items() if isinstance(v, str)), key=lambda x: x["command"]),
    }


def tell(text):
    try:
        done = subprocess.run([CONFIG["notify"]], input=text, text=True, capture_output=True, timeout=30)
    except (OSError, subprocess.TimeoutExpired) as e:
        print("butler-integration-check: could not tell Aaron: %s" % e, file=sys.stderr)
        return False
    if done.returncode != 0:
        print("butler-integration-check: butler-notify failed with exit %d" % done.returncode, file=sys.stderr)
    return done.returncode == 0


def write_file(path, text, mode=0o640):
    temporary = path + ".tmp"
    with open(temporary, "w") as f:
        f.write(text)
    os.chmod(temporary, mode)
    os.replace(temporary, path)


def main(argv):
    with open(os.environ["INTEGRATIONS_CONFIG"]) as f:
        CONFIG.update(json.load(f))
    ids = argv[1:] if len(argv) > 1 and argv[0] == "only" else None
    now = time.time()
    results = run_all(ids, now)
    for r in results:
        print("%-5s %s: %s%s" % (r["status"].upper() if r["status"] != "not connected" else "UNSET", r["id"], r["cause"], (" | fix: " + r["fix"]) if r["status"] in ("fail", "warn", "not connected") and r["fix"] else ""))
    if ids:
        return 0
    state_path = os.path.join(CONFIG["state"], "state.json")
    state = read_json(state_path, {}) or {}
    new, soon, state = choose_alerts(results, state, now)
    text = alert_text(new, soon)
    if text and not tell(text):
        # Untold, so the next run tells it: what was failing stays as it was, and an expiry stays untold.
        before = read_json(state_path, {}) or {}
        state["failing"] = sorted(set(state["failing"]) - {r["id"] for r in new})
        for r in soon:
            if before.get("expiryTold", {}).get(r["id"]) != int(r["expires"]):
                state["expiryTold"].pop(r["id"], None)
        new, soon = [], []
    document = status_document(results, now, CONFIG.get("coverage", {}))
    write_file(CONFIG["out"], json.dumps(document, ensure_ascii=False, indent=1))
    write_file(state_path, json.dumps(state), 0o600)
    history = os.path.join(CONFIG["state"], "history.jsonl")
    lines = []
    try:
        with open(history) as f:
            lines = f.readlines()[-499:]
    except OSError:
        pass
    lines.append(json.dumps({"at": int(now), "summary": document["summary"], "failing": state["failing"]}) + "\n")
    write_file(history, "".join(lines), 0o600)
    counts = document["summary"]
    print("butler-integration-check: %d pass, %d warn, %d fail, %d not connected, %d off; told Aaron of %d" % (counts["pass"], counts["warn"], counts["fail"], counts["not connected"], counts["off"], len(new) + len(soon)))
    # A failing integration never fails the unit: the result is in the file, and Aaron has been told.
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
