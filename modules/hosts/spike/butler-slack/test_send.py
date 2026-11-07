# Offline test of slack-send against a fake Slack: each verb calls the one method it should with the exact text,
# edit and delete refuse a message slack-send never posted, a missing scope is named, text too long for the
# approval is refused before anything is sent, every write reaches the audit spool, and the rate limit holds.
import importlib.util
import json
import os
import sys
import tempfile

home = tempfile.mkdtemp()
os.environ["HOME"] = home
os.environ["BUTLER_THREAD_ID"] = "123"
os.environ["BUTLER_THREAD_TITLE"] = "Slack test"
spec = importlib.util.spec_from_file_location("send", sys.argv[1])
send = importlib.util.module_from_spec(spec)
spec.loader.exec_module(send)


class Fake(send.Slack):
    def __init__(self, scopes=("chat:write", "reactions:write", "im:write")):
        super().__init__("xoxp-test")
        self.calls = []
        self.scopes = set(scopes)
        self.n = 0

    def fetch(self, method, params, post):
        self.calls.append((method, dict(params), post))
        need = {"chat.postMessage": "chat:write", "chat.update": "chat:write", "chat.delete": "chat:write", "reactions.add": "reactions:write", "conversations.open": "im:write"}.get(method)
        if need and need not in self.scopes:
            return {"ok": False, "error": "missing_scope", "needed": need}
        if method == "users.conversations":
            return {"ok": True, "channels": [{"id": "C222222", "name": "general"}]}
        if method == "users.list":
            return {"ok": True, "members": [{"id": "U0444444", "name": "sam", "profile": {"display_name": "Sam"}}, {"id": "U0555555", "name": "jo", "profile": {}}, {"id": "U0666666", "name": "old", "deleted": True}]}
        if method == "conversations.open":
            return {"ok": True, "channel": {"id": "D333333"}}
        if method == "chat.postMessage":
            self.n += 1
            return {"ok": True, "channel": params["channel"], "ts": f"500.00000{self.n}"}
        return {"ok": True}


def fails(fn, needle):
    try:
        fn()
    except send.Failure as failure:
        assert needle in str(failure), (needle, str(failure))
        return
    except SystemExit:
        assert needle == "usage", needle
        return
    raise AssertionError(f"expected a failure with {needle}")


now = 1_800_000_000
slack = Fake()
assert send.run(slack, ["post", "#general"], "Hello team\n", now).startswith("Sent to #general")
assert slack.calls[-1] == ("chat.postMessage", {"channel": "C222222", "text": "Hello team"}, True), slack.calls[-1]
send.run(slack, ["reply", "#general", "100.000001"], "In thread", now)
assert slack.calls[-1][1] == {"channel": "C222222", "text": "In thread", "thread_ts": "100.000001"}
send.run(slack, ["post", "@Sam"], "Hi", now)
assert slack.calls[-2] == ("conversations.open", {"users": "U0444444"}, True) and slack.calls[-1][1]["channel"] == "D333333"
send.run(slack, ["post", "@sam,@jo"], "Hi both", now)
assert slack.calls[-2] == ("conversations.open", {"users": "U0444444,U0555555"}, True)
send.run(slack, ["react", "#general", "100.000001", ":thumbsup:"], "", now)
assert slack.calls[-1] == ("reactions.add", {"channel": "C222222", "timestamp": "100.000001", "name": "thumbsup"}, True)

# Only Butler's own messages may be edited or deleted.
fails(lambda: send.run(slack, ["edit", "#general", "100.000001"], "changed", now), "not posted by slack-send")
fails(lambda: send.run(slack, ["delete", "#general", "100.000001"], "", now), "not posted by slack-send")
send.run(slack, ["edit", "#general", "500.000001"], "Hello everyone", now)
assert slack.calls[-1] == ("chat.update", {"channel": "C222222", "ts": "500.000001", "text": "Hello everyone"}, True)
send.run(slack, ["delete", "#general", "500.000001"], "", now)
assert slack.calls[-1][0] == "chat.delete"

# Nothing is sent for empty, control-character or over-long text, or a bad shape.
before = len(slack.calls)
fails(lambda: send.run(slack, ["post", "#general"], "  \n", now), "empty")
fails(lambda: send.run(slack, ["post", "C222222"], "an id", now), "usage")
fails(lambda: send.run(slack, ["post", "U0444444"], "an id", now), "usage")
fails(lambda: send.run(slack, ["post", "general"], "no hash", now), "usage")
fails(lambda: send.run(slack, ["post", "@old"], "deleted", now), "no person")
fails(lambda: send.run(slack, ["post", "#random"], "not a member", now), "no channel named #random")
fails(lambda: send.run(slack, ["react", "#general", "1.2", "eyes"], "hidden text", now), "takes no text")
fails(lambda: send.run(slack, ["post", "#general"], "bell\x07", now), "control characters")
fails(lambda: send.run(slack, ["post", "#general"], "x" * 800, now), "too long")
fails(lambda: send.run(slack, ["post", "#general", "extra"], "hi", now), "usage")
fails(lambda: send.run(slack, ["react", "#general", "1.2", "bad emoji!"], "", now), "usage")
assert all(method in ("users.conversations", "users.list") for method, _, _ in slack.calls[before:]), slack.calls[before:]

# A missing scope is named.
fails(lambda: send.run(Fake(scopes=()), ["post", "#general"], "hi", now), "lacks chat:write")

# Every write is in the audit spool with its channel and text.
spool = open(os.path.join(home, ".local/state/slack-send/audit-spool")).read()
assert "post to #general (C222222)" in spool and "Hello team" in spool and "[thread 123 \"Slack test\"]" in spool, spool
assert "edit C222222 500.000001: Hello everyone" in spool and "react :thumbsup:" in spool and "delete C222222 500.000001" in spool
assert "xoxp" not in spool

# The rate limit holds past PER_HOUR writes in an hour.
os.remove(os.path.join(home, ".local/state/slack-send/writes"))
for _ in range(send.PER_HOUR):
    send.run(slack, ["post", "#general"], "again", now + 10)
fails(lambda: send.run(slack, ["post", "#general"], "one too many", now + 20), "last hour")
send.run(slack, ["post", "#general"], "an hour later", now + 3700)

print(json.dumps({"ok": True, "calls": len(slack.calls)}))
