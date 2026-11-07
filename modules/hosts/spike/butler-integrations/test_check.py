"""Offline tests of butler-integration-check: coverage names real checks, secrets never reach a cause or an alert,
alerts go out once, never for a source not connected yet, the writers' gates are judged from the manifest, a broken
check never stops the rest, and a few checks against fake services and files.

usage: python3 test_check.py <check.py> <coverage.json>
"""

import importlib.util
import json
import os
import sys
import tempfile
import time

spec = importlib.util.spec_from_file_location("check", sys.argv[1])
check = importlib.util.module_from_spec(spec)
spec.loader.exec_module(check)
with open(sys.argv[2]) as f:
    coverage = json.load(f)

failures = []


def expect(condition, what):
    print(("ok   " if condition else "FAIL ") + what)
    if not condition:
        failures.append(what)


# Coverage names only checks check.py has, and every check covers some command or is a platform check.
known = set(check.CHECKS)
for command, value in sorted(coverage.items()):
    if isinstance(value, list):
        unknown = [i for i in value if i not in known]
        expect(not unknown, "coverage of %s names real checks %s" % (command, unknown or ""))
    else:
        expect(value.startswith("none: ") and len(value) > 10, "%s gives its reason for no live check" % command)
used = {i for v in coverage.values() if isinstance(v, list) for i in v}
platform = {"inbox-monitor", "certificates", "disk", "backlogic-runner", "backlogic-tunnel", "backlogic-peer", "chat-cache"}
expect(not (known - used - platform), "every check covers a command or the platform: %s" % sorted(known - used - platform))

# Secrets and addresses never survive into a cause.
samples = [
    "Bearer abcdEFGH1234567890abcdEFGH1234567890",
    "token: xoxp-1234567890-abcdefghij",
    "sk-proj-abcdefgh12345678",
    "ghp_ABCDEFGHIJKLMNOP1234",
    "github_pat_11ABCDEFG0123456789",
    "eyJhbGciOiJIUzI1NiJ9.eyJleHAiOjE3MDAwMDAwMDB9.c2lnbmF0dXJl",
    "password=hunter2hunter2hunter2x9",
    "mail aaron@example.com refused",
]
for sample in samples:
    out = check.redact(sample)
    expect("[cut]" in out and not any(part in out for part in ("abcdEFGH1234", "xoxp-1234", "sk-proj", "ghp_", "github_pat", "eyJ", "hunter2", "aaron@")), "redacts %r" % sample[:12])
for plain in ("the token expires in 9 days", "Google refused the saved login", "/var/lib/secrets/butler-github-backlogic-token is empty", "HTTP 401"):
    expect(check.redact(plain) == plain, "leaves %r alone" % plain)
expect("\n" not in check.redact("a\nb") and len(check.redact("x " * 500)) <= 240, "a cause is one short line")

# Temporary failures are degraded, not failing.
expect(check.fail("timed out", "")["status"] == "warn", "a timeout is a warning")
expect(check.fail("Slack refused the token: invalid_auth", "x")["status"] == "fail", "a refusal is a failure")
expect(check.fail("HTTP 503", "")["status"] == "warn", "a 503 is a warning")
expect(check.fail("Slack refused the token: HTTP 0", "x")["status"] == "warn" and check.fail("work-google: could not reach Google", "x")["status"] == "warn", "no answer at all is a warning, not a refusal")

# Alerts: a new failure once, never a known one, never a source not connected, an expiry once per expiry.
now = 1_800_000_000
day = 86400


def r(id, status, expires=None, cause="c", fix="f"):
    return {"id": id, "name": id.title(), "group": "g", "status": status, "cause": cause, "fix": fix, "expires": expires}


results = [r("up", "fail"), r("slack-read", "pass"), r("drive", "not connected"), r("github-issues-token", "pass", now + 9 * day), r("certificates", "pass", now + 60 * day)]
new, soon, state = check.choose_alerts(results, {}, now)
expect([x["id"] for x in new] == ["up"], "a new failure is told")
expect([x["id"] for x in soon] == ["github-issues-token"], "a token expiring within 14 days is told, a far one is not")
text = check.alert_text(new, soon)
expect("Up" in text and "Fix: f" in text and "Drive" not in text, "the alert names the failure and its fix, not the unconnected source")
new2, soon2, state2 = check.choose_alerts(results, state, now + 6 * 3600)
expect(not new2 and not soon2, "a known open failure and an expiry already told are not told again")
results3 = [r("up", "pass"), r("slack-read", "pass"), r("github-issues-token", "pass", now + 300 * day)]
_, _, state3 = check.choose_alerts(results3, state2, now + day)
new4, _, _ = check.choose_alerts([r("up", "fail")], state3, now + 2 * day)
expect([x["id"] for x in new4] == ["up"], "a failure that cleared and came back is told again")
expect(check.alert_text([], []) == "", "nothing new tells nothing")
new5, _, _ = check.choose_alerts([r("drive", "not connected")], {}, now)
expect(not new5, "a source never logged in is never told")

# The writers' gates, judged from a fixture manifest, never run.
with tempfile.TemporaryDirectory() as tmp:
    program = os.path.join(tmp, "prog")
    with open(program, "w") as f:
        f.write("#!/bin/sh\n")
    os.chmod(program, 0o755)
    manifest = {"commands": [
        {"name": "mail-send", "path": program, "rules": [{"match": ["*", "*", "*"], "lanes": ["interactive"], "egress": True, "taints": True, "outcome": {"kind": "message", "to": 1}}]},
        {"name": "calendar", "path": program, "rules": [{"match": ["agenda"], "lanes": ["call"]}, {"match": ["create", "**"], "lanes": ["interactive"], "acts": True}, {"match": ["delete", "**"], "lanes": ["interactive"], "acts": True}]},
        {"name": "hevy", "path": program, "rules": [{"match": ["routine", "*"], "lanes": ["interactive", "cron"]}, {"match": ["routine", "draft", "*"], "lanes": ["interactive"]}, {"match": ["routine", "apply", "*", "*"], "lanes": ["interactive"], "acts": True}]},
    ]}
    writes = [
        {"command": "mail-send", "kind": "send", "calls": [["fastmail", "a@example.com", "Hi"]]},
        {"command": "calendar", "kind": "write", "calls": [["create", "calendar.x", "s", "e", "T"], ["delete", "calendar.x", "uid"]]},
        {"command": "hevy", "kind": "write", "calls": [["routine", "apply", "A", "0123"]]},
    ]
    expect(check.gate_problems(manifest, writes) == [], "wired gates pass, and a read rule beside a write is left alone")
    manifest["commands"][0]["rules"][0]["outcome"] = None
    manifest["commands"][1]["rules"][1]["acts"] = False
    problems = check.gate_problems(manifest, writes + [{"command": "slack-send", "kind": "send", "calls": [["post", "#x"]]}, {"command": "messenger-send", "kind": "send", "calls": [["room"]], "optional": True}])
    expect(any("mail-send" in p for p in problems) and any("calendar create" in p for p in problems), "an ungated send and a write without acts are caught: %s" % problems)
    expect(any("slack-send is missing" in p for p in problems) and not any("messenger" in p for p in problems), "a missing writer is caught, an optional one is not")
    expect(check.matches(["zone", "**"], ["zone", "create", "Gym"]) and not check.matches(["routine", "*"], ["routine", "apply", "A", "0"]) and check.matches(["*"], ["room"]) and not check.matches(["*"], []), "a rule takes a call as the daemon matches it: one word per star, the rest for a trailing **")

    # Checks against fake services and files.
    creds = os.path.join(tmp, "creds")
    os.mkdir(creds)
    os.environ["CREDENTIALS_DIRECTORY"] = creds

    def credential(name, value):
        with open(os.path.join(creds, name), "w") as f:
            f.write(value)

    calls = []

    def fake(answers):
        def http(method, url, headers=None, data=None, timeout=20):
            calls.append((method, url))
            for prefix, answer in answers.items():
                if url.startswith(prefix):
                    return answer
            return 0, {}, b"unreachable"
        check.http = http

    check.CONFIG.update({
        "slackRead": ["channels:history", "search:read"], "slackWrite": ["chat:write"], "slackWriteLookup": ["users:read"],
        "feedsStatus": os.path.join(tmp, "feeds.json"), "homeAssistant": "http://ha", "commands": {},
    })
    slack = check.CHECKS["slack-read"]["run"]
    expect(slack(now)["status"] == "not connected", "Slack without a token is not connected")
    credential("slack-token", "xoxp-test-token-0000")
    fake({"https://slack.com/api/auth.test": (200, {"x-oauth-scopes": "channels:history,search:read"}, b'{"ok":true}')})
    expect(slack(now)["status"] == "pass", "Slack with every read scope passes")
    fake({"https://slack.com/api/auth.test": (200, {"x-oauth-scopes": "channels:history"}, b'{"ok":true}')})
    res = slack(now)
    expect(res["status"] == "fail" and "search:read" in res["cause"] and res["fix"] == "sudo butler-slack-login", "a lost scope fails with the login as its fix")
    fake({"https://slack.com/api/auth.test": (200, {}, b'{"ok":false,"error":"token_revoked"}')})
    expect(slack(now)["status"] == "fail", "a revoked token fails")
    credential("slack-write-token", "xoxp-write-0000")
    fake({"https://slack.com/api/auth.test": (200, {"x-oauth-scopes": "chat:write,users:read"}, b'{"ok":true}')})
    expect(check.CHECKS["slack-write"]["run"](now)["status"] == "pass" and all("chat.postMessage" not in u for _, u in calls), "the writer is checked with auth.test alone, never a post")

    credential("home-assistant-token", "eyJhbGciOiJIUzI1NiJ9.%s.sig" % check.base64.urlsafe_b64encode(json.dumps({"exp": now + 5 * day}).encode()).decode().rstrip("="))
    fake({"http://ha/api/": (200, {}, b'{"message":"API running."}')})
    res = check.CHECKS["home-assistant"]["run"](now)
    expect(res["status"] == "warn" and res["expires"] == now + 5 * day, "a Home Assistant token expiring in 5 days warns with its expiry")
    fake({"http://ha/api/": (401, {}, b"")})
    expect(check.CHECKS["home-assistant"]["run"](now)["status"] == "fail", "a refused Home Assistant token fails")

    with open(check.CONFIG["feedsStatus"], "w") as f:
        json.dump({"spotify": {"state": "needs-login", "message": "needs Aaron's Spotify login"}, "steam": {"state": "connected", "checked": time.strftime("%Y-%m-%dT%H:%M:%S+00:00", time.gmtime(now - 1800))},
                   "paypal": {"state": "failing", "message": "HTTP 401"}}, f)
    expect(check.CHECKS["feed-spotify"]["run"](now)["status"] == "not connected", "a feed waiting on a login is not connected")
    expect(check.CHECKS["feed-steam"]["run"](now)["status"] == "pass", "a fresh connected feed passes")
    res = check.CHECKS["feed-paypal"]["run"](now)
    expect(res["status"] == "fail" and res["fix"] == "sudo butler-feeds-login paypal", "a refused feed fails with its login")
    expect(check.CHECKS["feed-letterboxd"]["run"](now)["status"] == "not connected", "a feed that never ran is not connected")

    # A broken check never stops the rest, and the status file says nothing secret.
    check.CHECKS["zz-broken"] = {"id": "zz-broken", "name": "Broken", "group": "g", "run": lambda now: 1 / 0}
    fake({"https://slack.com/api/auth.test": (200, {}, b'{"ok":false,"error":"token_revoked"}')})
    out = check.run_all(["slack-read", "zz-broken"], now)
    expect([x["status"] for x in out] == ["fail", "fail"] and "ZeroDivisionError" in out[1]["cause"], "a check that raises is a failure, and the others still run")
    del check.CHECKS["zz-broken"]
    doc = check.status_document(out, now, coverage)
    blob = json.dumps(doc)
    expect("xoxp-test" not in blob and doc["noLiveCheck"] and doc["summary"]["fail"] == 2, "the status file holds no token and lists the commands without a live check")

print("%d failed" % len(failures))
sys.exit(1 if failures else 0)
