# Butler's one way to write to Aaron's work Slack workspace, as Aaron, with a user token of its own, from a second
# Slack app with the write scopes, which the read-only reader never holds.
#
# Every verb is gated by the daemon exactly like mail-send: its rule taints the thread, goes out and is the outcome
# `message` to the channel in its first argument, so outside a mission that names that channel Aaron approves the
# exact channel, verb and text through a Discord button, and the text is refused when the approval could not show it
# whole. It posts, replies in a thread, reacts, and edits or deletes only messages it posted itself, which it records
# in its sent log; it never marks anything read, joins, invites, leaves or changes a channel.
# Every write is appended to audit/slack-send in butler's memory with its channel and text.
import fcntl
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime

CREDENTIAL = "@credential@"
MEMORY_AUDIT = "@memoryAudit@"
API = "https://slack.com/api/"
STATE = os.path.join(os.environ.get("HOME", "/tmp"), ".local/state/slack-send")
# The daemon shows an approval's call whole up to 1500 characters, but clips it to as little as 260 when it merges
# several mission extensions into one card, so the text is kept short enough to show whole there too.
APPROVAL_LIMIT = 700
PER_HOUR = 20
# The scopes each verb needs, named when Slack refuses one so Aaron knows what to add.
WRITE_SCOPES = {
    "post": "chat:write (and im:write to open a DM with a person by their U… id)",
    "reply": "chat:write",
    "react": "reactions:write",
    "edit": "chat:write",
    "delete": "chat:write",
}

USAGE = """usage: slack-send post <to>              (text on stdin)
       slack-send reply <to> <thread ts>   (text on stdin)
       slack-send react <to> <ts> <emoji name>
       slack-send edit <to> <ts>           (new text on stdin; only a message slack-send posted)
       slack-send delete <to> <ts>         (only a message slack-send posted)
<to> is #channel-name for a channel Aaron is in, @handle for a DM with one person, or @a,@b for a group DM,
handles as slack users shows them, so Aaron's approval names who it goes to; ids are refused"""


class Failure(Exception):
    pass


def usage():
    print(USAGE, file=sys.stderr)
    sys.exit(2)


class Slack:
    """The Web API. Tests replace `fetch`."""

    def __init__(self, token):
        self.token = token

    def fetch(self, method, params, post):
        data = urllib.parse.urlencode(params).encode() if post else None
        url = API + method + ("" if post else "?" + urllib.parse.urlencode(params))
        request = urllib.request.Request(url, data=data, headers={"Authorization": f"Bearer {self.token}"})
        # Only a 429, which Slack answers before acting, is retried, once, so a write that may have landed is never
        # sent twice, and every wait stays inside the daemon's 60 second limit.
        for attempt in range(2):
            try:
                with urllib.request.urlopen(request, timeout=15) as response:
                    return json.loads(response.read())
            except urllib.error.HTTPError as error:
                if error.code == 429 and attempt == 0:
                    time.sleep(min(int(error.headers.get("Retry-After") or 5), 10))
                    continue
                raise Failure(f"HTTP {error.code} from Slack")
            except urllib.error.URLError as error:
                raise Failure(f"could not reach Slack ({error.reason}); {'it may have gone, so check with slack history before trying again' if post else 'nothing was sent'}")
            except (OSError, ValueError) as error:
                raise Failure(f"Slack did not answer properly ({error}); {'it may have gone, so check with slack history before trying again' if post else 'nothing was sent'}")
        raise Failure("Slack kept rate limiting; nothing was sent")

    def call(self, method, verb, post=True, **params):
        data = self.fetch(method, {k: v for k, v in params.items() if v not in (None, "")}, post)
        if not data.get("ok"):
            error = data.get("error") or "unknown error"
            if error == "missing_scope":
                raise Failure(f"the Slack token lacks {data.get('needed') or WRITE_SCOPES[verb]}; Aaron adds it to the writing Slack app's User Token Scopes, reinstalls it and runs sudo butler-slack-login --write (the slack-send skill says how)")
            raise Failure(f"{method} failed: {error}")
        return data


def text_of(verb, args, stdin):
    """The text from stdin, checked so the approval shows exactly what goes out."""
    text = stdin.rstrip("\n")
    if not text.strip():
        raise Failure("the text on stdin is empty")
    if re.search(r"[\x00-\x08\x0b-\x1f\x7f]", text):
        raise Failure("the text has control characters other than newlines and tabs; remove them")
    shown = len(json.dumps({"args": [verb, *args], "stdin": stdin}, indent=1))
    if shown > APPROVAL_LIMIT:
        raise Failure("the text is too long for Aaron's approval to show all of it; shorten it")
    return text


def pages(slack, method, key, verb, **params):
    cursor = ""
    for _ in range(50):
        data = slack.call(method, verb, post=False, limit=200, cursor=cursor, **params)
        yield from data.get(key) or []
        cursor = (data.get("response_metadata") or {}).get("next_cursor") or ""
        if not cursor:
            return


def person(slack, handle, verb):
    """A user id from the handle slack users shows, its name or display name, matched exactly."""
    found = [u["id"] for u in pages(slack, "users.list", "members", verb)
             if not u.get("deleted") and handle in (u.get("name"), (u.get("profile") or {}).get("display_name"))]
    if len(found) != 1:
        raise Failure(f"{'no' if not found else 'more than one'} person with the handle @{handle}; check slack users")
    return found[0]


def channel(slack, given, verb):
    """The conversation <to> names: #name a channel Aaron is in, @handle a DM, @a,@b a group DM."""
    if re.fullmatch(r"#[a-z0-9._-]+", given):
        for item in pages(slack, "users.conversations", "channels", verb, types="public_channel,private_channel", exclude_archived="true"):
            if item.get("name") == given[1:]:
                return item["id"]
        raise Failure(f"Aaron is in no channel named {given}")
    handles = given.split(",")
    if 1 <= len(handles) <= 8 and all(re.fullmatch(r"@[A-Za-z0-9._-]+", h) for h in handles) and len(set(handles)) == len(handles):
        users = ",".join(person(slack, h[1:], verb) for h in handles)
        return slack.call("conversations.open", verb, users=users)["channel"]["id"]
    usage()


def timestamp(given):
    if not re.fullmatch(r"[0-9]+\.[0-9]+", given):
        usage()
    return given


def sent_log():
    return os.path.join(STATE, "sent.jsonl")


def sent_by_butler(cid, ts):
    try:
        with open(sent_log()) as log:
            for line in log:
                try:
                    entry = json.loads(line)
                except ValueError:
                    continue
                if (entry.get("channel"), entry.get("ts")) == (cid, ts):
                    return True
    except OSError:
        pass
    return False


def remember(cid, ts):
    """Best effort: the message has gone, so a failure here must not read as a failed send."""
    try:
        os.makedirs(STATE, exist_ok=True)
        with open(sent_log(), "a") as log:
            fcntl.flock(log, fcntl.LOCK_EX)
            log.write(json.dumps({"channel": cid, "ts": ts, "at": int(time.time())}) + "\n")
    except OSError:
        print("slack-send: could not record the message, so it cannot be edited or deleted later", file=sys.stderr)


def rate_limit(now):
    """At most PER_HOUR writes an hour, so a looping turn cannot flood a colleague."""
    os.makedirs(STATE, exist_ok=True)
    path = os.path.join(STATE, "writes")
    with open(path + ".lock", "a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            with open(path) as f:
                recent = [int(line) for line in f if line.strip().isdigit() and int(line) > now - 3600]
        except FileNotFoundError:
            recent = []
        if len(recent) >= PER_HOUR:
            raise Failure(f"{PER_HOUR} Slack writes were made in the last hour, the most allowed; try again later")
        with open(path + ".new", "w") as f:
            f.write("".join(f"{t}\n" for t in recent + [now]))
        os.replace(path + ".new", path)


def audit(line):
    """Appends one line to audit/slack-send in butler's memory; never fails the write, which has happened."""
    thread = re.sub(r"[^0-9A-Za-z_-]", "", os.environ.get("BUTLER_THREAD_ID", ""))[:32]
    title = re.sub(r"[\t\r\n\"]", " ", os.environ.get("BUTLER_THREAD_TITLE", ""))[:60]
    named = f' "{title}"' if title else ""
    tag = f"[thread {thread}{named}] " if thread else ""
    now = datetime.now().astimezone()
    entry = f"{now:%Y-%m-%d}\t{now:%H:%M:%S %z} {tag}{re.sub(r'[\t\r\n]+', ' ', line)}\n"
    spool = os.path.join(STATE, "audit-spool")
    try:
        os.makedirs(STATE, exist_ok=True)
        with open(spool, "a") as f:
            fcntl.flock(f, fcntl.LOCK_EX)
            f.write(entry)
        if MEMORY_AUDIT.startswith("/"):
            subprocess.Popen([MEMORY_AUDIT, "slack-send", spool], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    except OSError:
        print("slack-send: could not write the audit line", file=sys.stderr)


def run(slack, argv, stdin, now):
    if not argv:
        usage()
    verb, args = argv[0], argv[1:]
    shapes = {"post": 1, "reply": 2, "react": 3, "edit": 2, "delete": 2}
    if verb not in shapes or len(args) != shapes[verb]:
        usage()
    text = text_of(verb, args, stdin) if verb in ("post", "reply", "edit") else None
    if text is None and stdin.strip():
        raise Failure(f"{verb} takes no text, and the approval would have shown some; call it with none")
    if verb == "react":
        emoji = args[2].strip(":")
        if not re.fullmatch(r"[a-z0-9_+'-]{1,100}", emoji):
            usage()
    ts = timestamp(args[1]) if len(args) > 1 else None
    cid = channel(slack, args[0], verb)
    if verb in ("edit", "delete") and not sent_by_butler(cid, ts):
        raise Failure("that message was not posted by slack-send, and only Butler's own messages may be edited or deleted")
    rate_limit(now)
    if verb in ("post", "reply"):
        data = slack.call("chat.postMessage", verb, channel=cid, text=text, thread_ts=ts if verb == "reply" else None)
        remember(data.get("channel") or cid, data.get("ts", ""))
        audit(f"{verb} to {args[0]} ({cid}){' in thread ' + ts if ts else ''}, ts {data.get('ts', '?')}: {text}")
        return f"Sent to {args[0]}{' in thread ' + ts if ts else ''}, ts {data.get('ts', '?')}"
    if verb == "react":
        slack.call("reactions.add", verb, channel=cid, timestamp=ts, name=emoji)
        audit(f"react :{emoji}: on {cid} {ts}")
        return f"Reacted :{emoji}: on {ts} in {args[0]}"
    if verb == "edit":
        slack.call("chat.update", verb, channel=cid, ts=ts, text=text)
        audit(f"edit {cid} {ts}: {text}")
        return f"Edited {ts} in {args[0]}"
    slack.call("chat.delete", verb, channel=cid, ts=ts)
    audit(f"delete {cid} {ts}")
    return f"Deleted {ts} in {args[0]}"


def main():
    try:
        with open(CREDENTIAL) as f:
            token = f.read().strip()
    except OSError:
        token = ""
    if not token:
        print("slack-send: there is no Slack token for writing yet; Aaron runs sudo butler-slack-login --write on spike (the slack-send skill says how)", file=sys.stderr)
        sys.exit(78)
    stdin = "" if sys.stdin is None or sys.stdin.isatty() else sys.stdin.read(64 * 1024)
    try:
        print(run(Slack(token), sys.argv[1:], stdin, int(time.time())))
    except Failure as failure:
        print(f"slack-send: {failure}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
