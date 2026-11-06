# Offline test of butler's Slack reader against a fake Slack: long messages print whole, from blocks
# or text, threads page through every reply, shared messages, unfurls and file text show, the token
# never leaves Slack's hosts or reaches the output, and the output stops before the daemon's limit.
import contextlib
import importlib.util
import io
import json
import sys
import urllib.parse

spec = importlib.util.spec_from_file_location("slack", sys.argv[1])
slack = importlib.util.module_from_spec(spec)
spec.loader.exec_module(slack)

TOKEN = "xoxp-test-secret"
LONG = " ".join(f"word{n}" for n in range(3000))  # about 26,000 characters, past every old cap
TAIL = "the very last sentence of the feedback."

USERS = [{"id": "U1", "name": "cd", "real_name": "Colleague D", "profile": {"display_name": "cd"}}, {"id": "U2", "name": "aaron", "profile": {"display_name": "Aaron"}}]
CHANNELS = [{"id": "C111111", "name": "general", "is_member": True, "num_members": 3}]
PARENT = {
    "ts": "100.000001", "thread_ts": "100.000001", "reply_count": 250, "user": "U1",
    "text": "short fallback",
    "blocks": [{"type": "rich_text", "elements": [
        {"type": "rich_text_section", "elements": [{"type": "text", "text": "Feedback for "}, {"type": "user", "user_id": "U2"}, {"type": "text", "text": ":\n"}]},
        {"type": "rich_text_list", "style": "ordered", "elements": [{"type": "rich_text_section", "elements": [{"type": "text", "text": "first point"}]}, {"type": "rich_text_section", "elements": [{"type": "text", "text": LONG + " " + TAIL}]}]},
        {"type": "rich_text_quote", "elements": [{"type": "text", "text": "quoted bit"}]},
    ]}],
}
REPLIES = [PARENT] + [{"ts": f"100.{n + 2:06d}", "thread_ts": "100.000001", "user": "U2", "text": f"reply {n}"} for n in range(250)]
SHARED = {
    "ts": "200.000001", "user": "U2", "text": "<@U1> see <https://example.com/x|this>",
    "attachments": [
        {"is_share": True, "author_name": "Colleague D", "channel_name": "general", "ts": "100.000001", "text": "x", "message_blocks": [{"message": {"blocks": PARENT["blocks"]}}]},
        {"service_name": "Docs", "title": "A doc", "title_link": "https://docs.example.com/1", "text": "unfurled preview text"},
    ],
    "files": [
        {"id": "F1", "name": "notes.txt", "filetype": "text", "mode": "snippet", "size": 30, "url_private": "https://files.slack.com/files-pri/T/notes.txt", "preview": "preview only"},
        {"id": "F2", "name": "evil.txt", "filetype": "text", "mode": "snippet", "size": 30, "url_private": "https://evil.example.com/steal", "preview": "evil preview"},
        {"id": "F3", "name": "plan", "filetype": "quip", "mode": "canvas", "size": 40, "url_private": "https://files.slack.com/files-pri/T/canvas"},
    ],
}


class Fake(slack.Slack):
    def __init__(self, scopes):
        super().__init__(TOKEN)
        self.granted_scopes = scopes
        self.hosts = []

    def fetch(self, url):
        parts = urllib.parse.urlsplit(url)
        self.hosts.append(parts.hostname)
        headers = {"x-oauth-scopes": ",".join(self.granted_scopes), "content-type": "application/json"}
        if parts.hostname == "files.slack.com":
            assert "files:read" in self.granted_scopes, "fetched a file without files:read"
            if parts.path.endswith("canvas"):
                return b"<html><body><h1>Plan</h1><p>canvas &amp; body</p></body></html>", {"content-type": "text/html"}
            return b"the whole snippet text", {"content-type": "text/plain"}
        assert parts.hostname == "slack.com", f"sent the token to {parts.hostname}"
        method = parts.path.rsplit("/", 1)[-1]
        query = dict(urllib.parse.parse_qsl(parts.query))
        if method == "users.list":
            data = {"members": USERS}
        elif method == "auth.test":
            data = {"user_id": "U2", "user": "aaron", "team": "Work"}
        elif method == "conversations.list":
            data = {"channels": CHANNELS}
        elif method == "conversations.replies":
            start = int(query.get("cursor") or 0)
            page = REPLIES[start:start + 100]
            data = {"messages": page, "response_metadata": {"next_cursor": str(start + 100) if start + 100 < len(REPLIES) else ""}}
        elif method == "conversations.history":
            everything = [PARENT, SHARED]
            if query.get("latest"):
                everything = [m for m in everything if m["ts"] == query["latest"]]
            data = {"messages": everything}
        elif method == "search.messages":
            data = {"messages": {"matches": [{"ts": "100.000001", "user": "U1", "text": "short fallback", "channel": {"id": "C111111", "name": "general"}}]}}
        else:
            raise AssertionError(method)
        return json.dumps({"ok": True, **data}).encode(), headers


def run(args, scopes=("search:read", "users:read")):
    fake = Fake(list(scopes))
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        slack.run(fake, args)
    text = out.getvalue()
    assert TOKEN not in text, "the token reached the output"
    return text, fake


# One long message prints whole from its blocks, with its list and quote.
text, _ = run(["message", "general", "100.000001"])
assert TAIL in text and "Feedback for @Aaron:" in text and "1. first point" in text and "2. word0" in text and "> quoted bit" in text, text[:400]

# A thread pages through every reply, past Slack's first page, and stays under the daemon's limit, saying how to read on.
text, _ = run(["thread", "C111111", "100.000001"])
assert TAIL in text and "reply 0\n" in text and "reply 120\n" in text, "a reply past the first page was lost"
assert len(text) < 50000
if "read on with" in text:
    last = text.rsplit("slack thread C111111 100.000001 ", 1)[1].split("`")[0]
    text, _ = run(["thread", "C111111", "100.000001", last])
    assert TAIL not in text
assert "reply 249\n" in text, "the rest of the thread could not be read"

# Shared messages, unfurls and files: the shared message whole, the preview text, files only from Slack's hosts.
text, fake = run(["message", "C111111", "200.000001"])
assert "@cd see this (https://example.com/x)" in text
assert "[shared message from Colleague D in #general, ts=100.000001]" in text and TAIL in text
assert "unfurled preview text" in text
assert "preview only" in text and "files:read would show it" in text
assert "files.slack.com" not in fake.hosts and "evil.example.com" not in fake.hosts
text, fake = run(["message", "C111111", "200.000001"], scopes=("files:read",))
assert "the whole snippet text" in text and "canvas & body" in text and "Plan" in text
assert "evil.example.com" not in fake.hosts and "evil preview" in text

# Search reads each match's own copy when the match has no blocks, so it prints whole too.
text, _ = run(["search", "feedback", "from:@cd"])
assert TAIL in text and "#general channel=C111111" in text

# History stops before the daemon's limit, saying how to read the rest.
many = [{**PARENT, "ts": f"300.{n:06d}", "reply_count": 0} for n in range(5)]
history = Fake.fetch


def fetch_many(self, url):
    if "conversations.history" in url:
        return json.dumps({"ok": True, "messages": many}).encode(), {}
    return history(self, url)


Fake.fetch = fetch_many
text, _ = run(["history", "general", "5"])
Fake.fetch = history
assert len(text) < 50000 and "more messages not shown" in text and "slack message <channel> <ts>" in text

# Scopes lists what is granted and what would help, never the token.
text, _ = run(["scopes"], scopes=("channels:history", "search:read"))
assert "granted: channels:history, search:read" in text and "missing, needed by slack:" in text and "files:read" in text

# A mention of an unknown user and Slack's entities stay readable.
assert slack.readable(Fake([]), "a &lt;b&gt; &amp; <!here>") == "a <b> & @here"
print("slack reader: all good")
