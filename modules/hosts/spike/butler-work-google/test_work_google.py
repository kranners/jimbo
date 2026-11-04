"""Runs work_google.py against a mock Google on loopback.

    python3 -I test_work_google.py work_google.py <zoneinfo dir>
"""

import base64
import contextlib
import datetime
import importlib.util
import io
import json
import os
import sys
import tempfile
import threading
import urllib.parse
import zoneinfo
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

zoneinfo.reset_tzpath([sys.argv[2]])

seen = []
state = {"refresh": "ok"}
melbourne = zoneinfo.ZoneInfo("Australia/Melbourne")
today = datetime.datetime.now(melbourne).date()


def at(hour, minute=0):
    return datetime.datetime.combine(today, datetime.time(hour, minute), melbourne).isoformat()


EVENTS = [
    {"summary": "Morning standup", "start": {"dateTime": at(9)}, "end": {"dateTime": at(9, 15)},
     "hangoutLink": "https://meet.google.com/abc-defg-hij",
     "attendees": [{"email": "me@example.com", "self": True, "responseStatus": "accepted"},
                   {"email": "sam@example.com", "responseStatus": "accepted"},
                   {"email": "room@resource.calendar.google.com", "resource": True}]},
    {"summary": "Maybe lunch talk", "start": {"dateTime": at(12)}, "end": {"dateTime": at(13)},
     "attendees": [{"email": "me@example.com", "self": True, "responseStatus": "tentative"}],
     "conferenceData": {"entryPoints": [{"entryPointType": "video", "uri": "https://meet.google.com/xyz"}]}},
    {"summary": "Declined thing", "start": {"dateTime": at(14)}, "end": {"dateTime": at(15)},
     "attendees": [{"email": "me@example.com", "self": True, "responseStatus": "declined"}]},
    {"summary": "Fresh invite", "start": {"dateTime": at(16)}, "end": {"dateTime": at(16, 30)},
     "attendees": [{"email": "me@example.com", "self": True, "responseStatus": "needsAction"}]},
    {"summary": "Cancelled", "status": "cancelled", "start": {"dateTime": at(17)}, "end": {"dateTime": at(18)}},
    {"summary": "Offsite", "start": {"date": today.isoformat()}, "end": {"date": (today + datetime.timedelta(days=1)).isoformat()}},
]


def encoded(text):
    return base64.urlsafe_b64encode(text.encode()).decode().rstrip("=")


class Google(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def answer(self, status, body):
        data = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        form = urllib.parse.parse_qs(self.rfile.read(length).decode())
        seen.append(("POST", self.path, form))
        assert self.path == "/token", self.path
        if state["refresh"] == "revoked":
            return self.answer(400, {"error": "invalid_grant", "error_description": "Token has been expired or revoked."})
        assert form["refresh_token"] == ["refresh-1"], form
        self.answer(200, {"access_token": "access-1", "expires_in": 3599})

    def do_GET(self):
        url = urllib.parse.urlparse(self.path)
        query = urllib.parse.parse_qs(url.query)
        seen.append(("GET", url.path, query))
        assert self.headers["Authorization"] == "Bearer access-1"
        path = url.path
        if path == "/gmail/v1/users/me/labels/INBOX":
            return self.answer(200, {"id": "INBOX", "messagesUnread": 7})
        if path == "/gmail/v1/users/me/messages":
            ids = [{"id": "18f0a1b2c3d4e5f6"}, {"id": "18f0a1b2c3d4e5f7"}][: int(query["maxResults"][0])]
            return self.answer(200, {"messages": ids})
        if path.startswith("/gmail/v1/users/me/messages/"):
            identifier = path.rsplit("/", 1)[1]
            headers = [{"name": "From", "value": '"Sam Lee" <sam@example.com>'},
                       {"name": "Subject", "value": f"Standup notes {identifier[-1]}"},
                       {"name": "To", "value": "me@example.com"}]
            message = {"id": identifier, "internalDate": "1793750400000", "labelIds": ["INBOX", "UNREAD"],
                       "payload": {"headers": headers, "mimeType": "multipart/alternative", "parts": [
                           {"mimeType": "text/html", "body": {"data": encoded("<p>html only</p>")}},
                           {"mimeType": "text/plain", "body": {"data": encoded("Plain notes body")}}]}}
            return self.answer(200, message)
        if path == "/calendar/v3/calendars/primary/events":
            assert query["singleEvents"] == ["true"]
            return self.answer(200, {"items": EVENTS})
        self.answer(404, {"error": {"message": "unknown"}})


server = ThreadingHTTPServer(("127.0.0.1", 0), Google)
threading.Thread(target=server.serve_forever, daemon=True).start()
base = f"http://127.0.0.1:{server.server_port}"

directory = tempfile.mkdtemp()
token = os.path.join(directory, "token.json")
os.environ.update({
    "WORK_GOOGLE_TOKEN": token,
    "WORK_GOOGLE_TZ": "Australia/Melbourne",
    "WORK_GOOGLE_OAUTH_BASE": base,
    "WORK_GOOGLE_GMAIL_BASE": base,
    "WORK_GOOGLE_CALENDAR_BASE": base,
})
specification = importlib.util.spec_from_file_location("work_google", sys.argv[1])
work = importlib.util.module_from_spec(specification)
specification.loader.exec_module(work)


def run(*arguments):
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        code = work.main(list(arguments))
    return code, out.getvalue(), err.getvalue()


failures = []


def check(name, condition, detail=""):
    print(("ok   " if condition else "FAIL ") + name)
    if not condition:
        failures.append(name)
        print(f"     {detail}")


# Only read-only scopes are ever asked for.
check("scopes are read-only", all(scope.endswith(".readonly") for scope in work.SCOPES), work.SCOPES)

def no_input(prompt=""):
    raise AssertionError("login prompted before it had a work address")


work.input = no_input
for arguments in (("login",), ("login", "not-an-address")):
    code, _, err = run(*arguments)
    check(f"{' '.join(arguments)} exits 2 without prompting", code == 2, err)

code, out, err = run("mail", "unread")
check("no token exits 78 naming the login", code == 78 and "butler-work-google-login" in err, err)
check("no token makes no request", not seen, seen)

with open(token, "w") as file:
    json.dump({"account": "me@example.com", "client_id": "id.apps.googleusercontent.com",
               "client_secret": "secret-1", "refresh_token": "refresh-1"}, file)

code, out, _ = run("mail", "unread-count")
check("unread count reads INBOX's label", code == 0 and out.strip() == "7", out)

code, out, _ = run("mail", "unread", "2")
check("unread lists ids, senders and subjects", code == 0 and "18f0a1b2c3d4e5f6" in out and "Sam Lee" in out and "Standup notes 6" in out and "unread" in out, out)
listing = [entry for entry in seen if entry[1] == "/gmail/v1/users/me/messages"][-1]
check("unread asks for unread inbox mail", listing[2]["q"] == ["in:inbox is:unread"], listing)
metadata = [entry for entry in seen if entry[1].endswith("18f0a1b2c3d4e5f6")][-1]
check("listings fetch headers alone", metadata[2]["format"] == ["metadata"], metadata)

code, out, _ = run("mail", "search", "from:sam", "standup")
listing = [entry for entry in seen if entry[1] == "/gmail/v1/users/me/messages"][-1]
check("search passes Gmail's syntax through", code == 0 and listing[2]["q"][0].startswith("from:sam standup"), listing)

code, out, _ = run("mail", "read", "18f0a1b2c3d4e5f6")
check("read prints headers and the plain body", code == 0 and "From: \"Sam Lee\"" in out and "Plain notes body" in out and "html only" not in out, out)

code, _, err = run("mail", "read", "../../send")
check("read refuses an id that is not Gmail's", code == 2, err)

for verb in ("archive", "send", "delete"):
    code, _, err = run("mail", verb, "18f0a1b2c3d4e5f6")
    check(f"mail {verb} is refused as read-only", code == 2 and "read-only" in err, err)

code, out, _ = run("calendar", "agenda")
check("agenda keeps accepted, tentative and invited meetings", code == 0 and "Morning standup" in out and "Maybe lunch talk\ttentative" in out and "Fresh invite\tinvited" in out, out)
check("agenda drops declined and cancelled ones", "Declined thing" not in out and "Cancelled" not in out, out)
check("agenda counts people, not rooms", "Morning standup\taccepted\t2\t" in out, out)
check("agenda gives the Meet link", "https://meet.google.com/abc-defg-hij" in out and "https://meet.google.com/xyz" in out, out)
check("agenda never prints an attendee's address", "sam@example.com" not in out and "me@example.com" not in out, out)
check("agenda shows all-day events", "Offsite" in out, out)

code, out, _ = run("calendar", "brief")
lines = out.strip().splitlines()
check("brief gives times and titles alone", code == 0 and all(len(line.split("\t")) == 3 for line in lines) and "meet.google" not in out and "tentative" not in out, out)

code, out, _ = run("calendar", "events", "2026-11-05", "2026-11-06")
query = [entry for entry in seen if entry[1] == "/calendar/v3/calendars/primary/events"][-1][2]
check("events passes its window", code == 0 and query["timeMin"][0].startswith("2026-11-05T00:00:00"), query)

code, _, err = run("calendar", "events", "2026-11-05", "2027-11-05")
check("events refuses a window over 62 days", code == 2, err)

code, _, err = run("calendar", "agenda", "-1")
check("agenda refuses a bad day count", code == 2, err)

state["refresh"] = "revoked"
code, _, err = run("calendar", "agenda")
check("a revoked login exits 75 naming the login", code == 75 and "butler-work-google-login" in err, err)

check("only mock Google was reached", all(entry[1].startswith(("/token", "/gmail/", "/calendar/")) for entry in seen), seen)

server.shutdown()
if failures:
    print(f"{len(failures)} failed")
    sys.exit(1)
print("all passed")
