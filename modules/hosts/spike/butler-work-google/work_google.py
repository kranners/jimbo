"""Read-only access to Aaron's work Google Workspace mail and calendar.

The token file holds Aaron's own OAuth desktop client and a refresh token for
gmail.readonly and calendar.readonly alone, so nothing here can send, archive,
delete or change anything.
Each call trades the refresh token for an access token kept in memory for that
call alone, and nothing read is written anywhere.

    work-google mail unread-count
    work-google mail unread [count] | list [count] | search <words>... | read <id>
    work-google calendar agenda [days] | brief [days] | events <start> <end>
    work-google login <work address>   (as butler, interactively, once)
"""

import base64
import datetime
import hashlib
import html
import json
import os
import re
import secrets
import sys
import urllib.error
import urllib.parse
import urllib.request
import zoneinfo

SCOPES = [
    "https://www.googleapis.com/auth/gmail.readonly",
    "https://www.googleapis.com/auth/calendar.readonly",
]
TOKEN = os.environ.get("WORK_GOOGLE_TOKEN", "")
LOGIN = os.environ.get("WORK_GOOGLE_LOGIN", "sudo -u butler butler-work-google-login <work address>")
TIMEZONE = zoneinfo.ZoneInfo(os.environ.get("WORK_GOOGLE_TZ", "Australia/Melbourne"))
# Only the flake check points these elsewhere, at its mock server.
OAUTH = os.environ.get("WORK_GOOGLE_OAUTH_BASE", "https://oauth2.googleapis.com")
GMAIL = os.environ.get("WORK_GOOGLE_GMAIL_BASE", "https://gmail.googleapis.com") + "/gmail/v1/users/me"
CALENDAR = os.environ.get("WORK_GOOGLE_CALENDAR_BASE", "https://www.googleapis.com") + "/calendar/v3"
AUTHORIZE = "https://accounts.google.com/o/oauth2/v2/auth"
REDIRECT = "http://127.0.0.1:8976"
READ_LIMIT = 40000


class Failure(Exception):
    def __init__(self, message, code=1):
        super().__init__(message)
        self.code = code


def usage():
    raise Failure(__doc__.split("\n\n", 2)[2].rstrip(), 2)


def request(url, data=None, token=None):
    headers = {"Accept": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    body = None
    if data is not None:
        body = urllib.parse.urlencode(data).encode()
        headers["Content-Type"] = "application/x-www-form-urlencoded"
    try:
        with urllib.request.urlopen(urllib.request.Request(url, data=body, headers=headers), timeout=30) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        try:
            detail = json.load(error)
        except ValueError:
            detail = {}
        raise GoogleError(error.code, detail) from None
    except urllib.error.URLError as error:
        raise Failure(f"work-google: could not reach Google: {error.reason}", 75) from None


class GoogleError(Exception):
    def __init__(self, status, detail):
        super().__init__(status)
        self.status = status
        self.detail = detail

    def reason(self):
        error = self.detail.get("error")
        if isinstance(error, dict):
            return error.get("message") or error.get("status") or str(self.status)
        return self.detail.get("error_description") or error or str(self.status)


def load_token():
    try:
        with open(TOKEN) as file:
            token = json.load(file)
    except FileNotFoundError:
        raise Failure(f"work-google: not logged in to the work Google account yet; Aaron runs `{LOGIN}` on spike once", 78) from None
    except (OSError, ValueError) as error:
        raise Failure(f"work-google: the token file is unreadable ({error}); Aaron runs `{LOGIN}` on spike again", 78) from None
    if not all(token.get(key) for key in ("client_id", "client_secret", "refresh_token")):
        raise Failure(f"work-google: the token file is incomplete; Aaron runs `{LOGIN}` on spike again", 78)
    return token


def access_token():
    token = load_token()
    try:
        answer = request(f"{OAUTH}/token", {
            "grant_type": "refresh_token",
            "client_id": token["client_id"],
            "client_secret": token["client_secret"],
            "refresh_token": token["refresh_token"],
        })
    except GoogleError as error:
        reason = error.reason()
        if error.detail.get("error") in ("invalid_grant", "unauthorized_client", "invalid_client"):
            raise Failure(f"work-google: Google refused the saved login ({reason}); Aaron runs `{LOGIN}` on spike again", 75) from None
        if "admin" in reason.lower() or error.detail.get("error") == "admin_policy_enforced":
            raise Failure(f"work-google: the work Google Workspace admin blocks this app ({reason}); the admin must trust its client ID", 77) from None
        raise Failure(f"work-google: Google refused the token refresh: {reason}", 1) from None
    return answer["access_token"]


def get(base, path, params=None, token=None):
    url = f"{base}/{path}"
    if params:
        url += "?" + urllib.parse.urlencode(params, doseq=True)
    try:
        return request(url, token=token)
    except GoogleError as error:
        if error.status == 403 and "admin" in error.reason().lower():
            raise Failure(f"work-google: the work Google Workspace admin blocks this: {error.reason()}", 77) from None
        raise Failure(f"work-google: Google answered {error.status}: {error.reason()}", 1) from None


def clean(text):
    return re.sub(r"[\x00-\x08\x0b-\x1f\x7f]", " ", text or "").strip()


# Mail

def headers_of(payload):
    return {header["name"].lower(): header["value"] for header in payload.get("headers", [])}


def sender_name(sender):
    match = re.match(r'\s*"?([^"<]*?)"?\s*<([^>]+)>', sender or "")
    if match and match.group(1):
        return f"{match.group(1)} <{match.group(2)}>"
    return clean(sender)


def envelopes(token, query, count):
    if not 1 <= count <= 50:
        usage()
    listing = get(GMAIL, "messages", {"q": query, "maxResults": count}, token)
    rows = []
    for message in listing.get("messages", []):
        detail = get(GMAIL, f"messages/{message['id']}", {
            "format": "metadata",
            "metadataHeaders": ["From", "Subject", "Date"],
        }, token)
        headers = headers_of(detail.get("payload", {}))
        when = datetime.datetime.fromtimestamp(int(detail.get("internalDate", "0")) / 1000, TIMEZONE)
        flags = "" if "UNREAD" not in detail.get("labelIds", []) else "unread"
        rows.append("\t".join([
            message["id"],
            when.strftime("%Y-%m-%d %H:%M"),
            sender_name(headers.get("from", "")),
            clean(headers.get("subject", "(no subject)")),
            flags,
        ]))
    if not rows:
        return "No messages."
    return "ID\tDATE\tFROM\tSUBJECT\tFLAGS\n" + "\n".join(rows)


def decode(data):
    return base64.urlsafe_b64decode(data + "=" * (-len(data) % 4)).decode("utf-8", "replace")


def body_of(payload):
    plain, rich = [], []

    def walk(part):
        kind = part.get("mimeType", "")
        data = part.get("body", {}).get("data")
        if data and kind == "text/plain":
            plain.append(decode(data))
        elif data and kind == "text/html":
            rich.append(decode(data))
        for child in part.get("parts", []):
            walk(child)

    walk(payload)
    if plain:
        return "\n".join(plain)
    if rich:
        text = re.sub(r"(?is)<(script|style).*?</\1>", "", "\n".join(rich))
        text = re.sub(r"(?i)<br\s*/?>|</p>|</div>|</tr>", "\n", text)
        text = html.unescape(re.sub(r"<[^>]+>", "", text))
        return re.sub(r"\n\s*\n+", "\n\n", text)
    return "(no text)"


def read_message(token, identifier):
    if not re.fullmatch(r"[0-9a-f]{8,32}", identifier):
        usage()
    detail = get(GMAIL, f"messages/{identifier}", {"format": "full"}, token)
    payload = detail.get("payload", {})
    headers = headers_of(payload)
    lines = [f"{name.title()}: {clean(headers[name])}" for name in ("from", "to", "cc", "date", "subject") if name in headers]
    text = "\n".join(lines) + "\n\n" + body_of(payload).strip() + "\n"
    encoded = text.encode()
    if len(encoded) > READ_LIMIT:
        text = encoded[:READ_LIMIT].decode("utf-8", "ignore") + "\n[cut off]\n"
    return text


def search_query(words):
    # Gmail's own search syntax, such as from:sam or subject:standup, passes through; anything else is searched as words.
    return " ".join(words) + " -in:chats"


def mail(arguments):
    if not arguments:
        usage()
    action, rest = arguments[0], arguments[1:]
    if action in ("archive", "move", "delete", "send", "flag"):
        raise Failure("work-google: the work account is read-only: it cannot archive, move, delete, flag or send", 2)
    if action == "unread-count":
        if rest:
            usage()
        token = access_token()
        return str(get(GMAIL, "labels/INBOX", token=token).get("messagesUnread", 0))
    if action in ("unread", "list"):
        if len(rest) > 1 or (rest and not rest[0].isdigit()):
            usage()
        count = int(rest[0]) if rest else 10
        query = "in:inbox is:unread" if action == "unread" else "in:inbox"
        return envelopes(access_token(), query, count)
    if action == "search":
        if not rest:
            usage()
        return envelopes(access_token(), search_query(rest), 20)
    if action == "read":
        if len(rest) != 1:
            usage()
        return read_message(access_token(), rest[0])
    if action == "mailboxes":
        return "INBOX (read-only; the work account has no archive here)"
    usage()


# Calendar

def parse_instant(text):
    if re.fullmatch(r"\d{4}-\d{2}-\d{2}", text):
        return datetime.datetime.combine(datetime.date.fromisoformat(text), datetime.time(), TIMEZONE)
    if re.fullmatch(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2})?([+-]\d{2}:\d{2}|Z)?", text):
        instant = datetime.datetime.fromisoformat(text.replace("Z", "+00:00"))
        return instant if instant.tzinfo else instant.replace(tzinfo=TIMEZONE)
    usage()


def response_of(event):
    for attendee in event.get("attendees", []):
        if attendee.get("self"):
            return attendee.get("responseStatus", "needsAction")
    return "accepted"


def meet_link(event):
    if event.get("hangoutLink"):
        return event["hangoutLink"]
    for point in event.get("conferenceData", {}).get("entryPoints", []):
        if point.get("entryPointType") == "video" and point.get("uri"):
            return point["uri"]
    return ""


def when(edge):
    if "dateTime" in edge:
        return datetime.datetime.fromisoformat(edge["dateTime"].replace("Z", "+00:00")).astimezone(TIMEZONE).strftime("%Y-%m-%d %H:%M")
    return edge.get("date", "")


def meetings(start, end):
    token = access_token()
    found, page = [], None
    for _ in range(10):
        params = {
            "timeMin": start.isoformat(),
            "timeMax": end.isoformat(),
            "singleEvents": "true",
            "orderBy": "startTime",
            "maxResults": 250,
            "timeZone": str(TIMEZONE),
        }
        if page:
            params["pageToken"] = page
        answer = get(CALENDAR, "calendars/primary/events", params, token)
        found += answer.get("items", [])
        page = answer.get("nextPageToken")
        if not page:
            break
    labels = {"accepted": "accepted", "tentative": "tentative", "needsAction": "invited"}
    rows = []
    for event in found:
        if event.get("status") == "cancelled":
            continue
        response = response_of(event)
        if response == "declined":
            continue
        rows.append({
            "start": when(event.get("start", {})),
            "end": when(event.get("end", {})),
            "title": clean(event.get("summary", "(no title)")),
            "response": labels.get(response, response),
            "attendees": len([a for a in event.get("attendees", []) if not a.get("resource")]),
            "meet": meet_link(event),
        })
    return rows


def agenda_window(rest):
    if len(rest) > 1 or (rest and not re.fullmatch(r"\d{1,2}", rest[0])) or (rest and int(rest[0]) < 1):
        usage()
    days = int(rest[0]) if rest else 1
    today = datetime.datetime.now(TIMEZONE).date()
    start = datetime.datetime.combine(today, datetime.time(), TIMEZONE)
    return start, datetime.datetime.combine(today + datetime.timedelta(days=days), datetime.time(), TIMEZONE)


def table(rows, brief):
    if not rows:
        return "No work meetings."
    if brief:
        return "\n".join(f"{row['start']}\t{row['end']}\t{row['title']}" for row in rows)
    lines = ["START\tEND\tTITLE\tRESPONSE\tATTENDEES\tMEET"]
    lines += [f"{r['start']}\t{r['end']}\t{r['title']}\t{r['response']}\t{r['attendees']}\t{r['meet']}" for r in rows]
    return "\n".join(lines)


def calendar(arguments):
    if not arguments:
        usage()
    action, rest = arguments[0], arguments[1:]
    if action in ("agenda", "brief"):
        return table(meetings(*agenda_window(rest)), action == "brief")
    if action == "events":
        if len(rest) != 2:
            usage()
        start, end = parse_instant(rest[0]), parse_instant(rest[1])
        if end <= start or end - start > datetime.timedelta(days=62):
            raise Failure("work-google: the end must come after the start, at most 62 days later", 2)
        return table(meetings(start, end), False)
    usage()


# Login, run by Aaron as butler on spike

def login(address):
    if not re.fullmatch(r"[^@\s]+@[^@\s]+", address):
        raise Failure(f"work-google: {address!r} is not an email address; run `{LOGIN}`", 2)
    if not TOKEN:
        raise Failure("work-google: no token path is set", 2)
    print(f"Logging butler in to the work Google account {address}, read-only: Gmail and Calendar.")
    print("Use the desktop OAuth client of a Google Cloud project with the Gmail and Calendar APIs enabled.")
    client_id = input("OAuth desktop client ID: ").strip()
    import getpass
    client_secret = getpass.getpass("OAuth desktop client secret (hidden): ").strip()
    if not re.fullmatch(r"[A-Za-z0-9._-]+\.apps\.googleusercontent\.com", client_id) or not re.fullmatch(r"[A-Za-z0-9._-]{10,}", client_secret):
        raise Failure("work-google: that does not look like a Google OAuth desktop client ID and secret", 2)
    verifier = secrets.token_urlsafe(64)
    state = secrets.token_urlsafe(24)
    challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).rstrip(b"=").decode()
    params = {
        "client_id": client_id,
        "redirect_uri": REDIRECT,
        "response_type": "code",
        "scope": " ".join(SCOPES),
        "access_type": "offline",
        "prompt": "consent",
        "include_granted_scopes": "false",
        "state": state,
        "code_challenge": challenge,
        "code_challenge_method": "S256",
    }
    params["login_hint"] = address
    params["hd"] = address.split("@", 1)[1]
    print()
    print("Open this link in a browser, sign in as the work account and allow read-only Gmail and Calendar access:")
    print()
    print(f"{AUTHORIZE}?{urllib.parse.urlencode(params)}")
    print()
    print(f"The browser then fails to load a {REDIRECT} page; that is expected.")
    redirected = input("Paste that page's whole address here: ").strip()
    query = urllib.parse.parse_qs(urllib.parse.urlparse(redirected).query)
    if query.get("error"):
        raise Failure(f"work-google: Google refused the sign-in: {query['error'][0]}", 1)
    if query.get("state", [""])[0] != state or not query.get("code"):
        raise Failure("work-google: that address is not the one this login started; run it again", 1)
    try:
        answer = request(f"{OAUTH}/token", {
            "grant_type": "authorization_code",
            "code": query["code"][0],
            "client_id": client_id,
            "client_secret": client_secret,
            "redirect_uri": REDIRECT,
            "code_verifier": verifier,
        })
    except GoogleError as error:
        raise Failure(f"work-google: Google refused the code: {error.reason()}", 1) from None
    granted = set(answer.get("scope", "").split())
    missing = [scope.rsplit("/", 1)[1] for scope in SCOPES if scope not in granted]
    if missing:
        raise Failure(f"work-google: the consent left out {', '.join(missing)}; run it again and tick every box", 1)
    if not answer.get("refresh_token"):
        raise Failure("work-google: Google sent no refresh token; run it again", 1)
    profile = get(GMAIL, "profile", token=answer["access_token"])
    signed_in = profile.get("emailAddress", "")
    if signed_in.lower() != address.lower():
        raise Failure(f"work-google: that signed in as {signed_in}, not {address}; run it again with the work account", 1)
    directory = os.path.dirname(TOKEN)
    os.makedirs(directory, mode=0o700, exist_ok=True)
    temporary = os.path.join(directory, f".token.{secrets.token_hex(4)}")
    descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, "w") as file:
        json.dump({
            "account": address,
            "client_id": client_id,
            "client_secret": client_secret,
            "refresh_token": answer["refresh_token"],
        }, file)
    os.replace(temporary, TOKEN)
    print(f"Logged in as {address}, read-only. butler can read it from its next tool call, with no restart.")


def main(arguments):
    try:
        if not arguments:
            usage()
        if arguments[0] == "mail":
            print(mail(arguments[1:]))
        elif arguments[0] == "calendar":
            print(calendar(arguments[1:]))
        elif arguments[0] == "login" and len(arguments) == 2:
            login(arguments[1])
        else:
            usage()
    except Failure as failure:
        print(str(failure), file=sys.stderr)
        return failure.code
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
