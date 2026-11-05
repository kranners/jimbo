"""Fixture runs of the sweep's classifier and of notify's decisions: silent seeding, the
runner going down and coming back once each, and the daily waiting-on-Aaron notice."""

import datetime as dt
import importlib.util
import os
import sys

os.environ["SWEEP_WAITING_DAYS"] = "3"
os.environ["SWEEP_WAITING_COUNT"] = "10"
spec = importlib.util.spec_from_file_location("sweep", os.path.join(os.path.dirname(__file__), "sweep.py"))
sweep = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sweep)

NOW = dt.datetime(2026, 11, 5, 6, 0, tzinfo=dt.timezone.utc)
failures = []


def check(name, ok):
    print(("ok   " if ok else "FAIL ") + name)
    if not ok:
        failures.append(name)


def iso(delta):
    return (NOW - delta).isoformat().replace("+00:00", "Z")


def snapshot(waiting=12, old_days=5, heartbeat=dt.timedelta(minutes=2), claimed=True, spread=1):
    tickets = []
    requests = []
    for n in range(waiting):
        tid = f"B-{100 + n}"
        tickets.append({"id": tid, "state": "waiting", "movedAt": iso(dt.timedelta(days=30)), "title": f"Question {n} <@everyone> `x`", "project": "p"})
        requests.append({"ticket": tid, "question": "which?", "askedAt": iso(dt.timedelta(days=old_days + n * spread))})
    tickets.append({"id": "B-1", "state": "todo", "movedAt": iso(dt.timedelta(hours=1)), "project": "p"})
    if claimed:
        tickets.append({"id": "B-2", "state": "claimed", "movedAt": iso(dt.timedelta(hours=1)), "project": "p",
                        "claim": {"heartbeatAt": iso(heartbeat)}})
    return {"now": iso(dt.timedelta()), "tickets": tickets, "requests": requests}


def summarise(snap):
    found, open_by_project, _, waiting, runner = sweep.classify(snap, {}, set())
    return {
        "open": sum(open_by_project.values()),
        "tickets": {kind: sorted(ids) for kind, ids in found.items()},
        "waiting": waiting,
        "runner": runner,
    }


# Classifier: waiting times come from the oldest open request, and runner facts are counted.
s = summarise(snapshot())
check("waiting timed by request", all(item["byRequest"] for item in s["waiting"]) and len(s["waiting"]) == 12)
check("runner counts", s["runner"]["liveClaims"] == 1 and s["runner"]["claimable"] == 1)

# First run seeds silently even with everything to say.
messages, state, log, seeding = sweep.decide(summarise(snapshot(heartbeat=dt.timedelta(hours=2))), None, NOW, "failed")
check("seeding sends nothing", seeding and "service" in state["down"] and state["waitingNotifiedAt"])
print("  seed log:", log)

# A healthy run with few old waiting tickets says nothing.
healthy = summarise(snapshot(waiting=5))
messages, state, _, _ = sweep.decide(healthy, {}, NOW, "active")
check("quiet when healthy and under the threshold", messages == [])

# The waiting notice: count, oldest age, three oldest with clean titles and links, then not again within a day.
messages, state, _, _ = sweep.decide(summarise(snapshot()), {}, NOW, "active")
text = messages[0] if messages else ""
print("  " + text.replace("\n", "\n  "))
check("waiting notice sent", len(messages) == 1 and "12 tickets" in text and "oldest 16 days" in text)
check("three oldest listed", text.count("\n- ") == 3 and "B-111" in text and "#B-111" in text)
check("titles cleaned", "<" not in text and "@" not in text and "`" not in text)
again, state2, _, _ = sweep.decide(summarise(snapshot()), state, NOW + dt.timedelta(hours=23), "active")
# Heartbeats in the fixture age with the clock, so only the waiting notice is compared here.
check("not again the same day", not any("waited on you" in m for m in again))
later, _, _, _ = sweep.decide(summarise(snapshot()), state2, NOW + dt.timedelta(hours=25), "active")
check("again the next day", sum("waited on you" in m for m in later) == 1)
young, _, _, _ = sweep.decide(summarise(snapshot(old_days=1, spread=0)), {}, NOW, "active")
check("under 3 days old does not count", young == [])

# The runner: down once, never repeated, back once after two clear sweeps.
calm = summarise(snapshot(waiting=0))
messages, state, _, _ = sweep.decide(calm, {}, NOW, "inactive")
check("service down told", len(messages) == 1 and "inactive" in messages[0] and "restart" in messages[0])
messages, state, _, _ = sweep.decide(calm, state, NOW, "inactive")
check("service down not repeated", messages == [])
messages, state, _, _ = sweep.decide(calm, state, NOW, "active")
check("one clear sweep is not yet recovery", messages == [])
messages, state, _, _ = sweep.decide(calm, state, NOW, "active")
check("recovery told once", len(messages) == 1 and "back" in messages[0])
messages, state, _, _ = sweep.decide(calm, state, NOW, "active")
check("recovery not repeated", messages == [])

stale = summarise(snapshot(waiting=0, heartbeat=dt.timedelta(minutes=40)))
messages, _, _, _ = sweep.decide(stale, {}, NOW, "active")
check("stale heartbeats told", len(messages) == 1 and "40 minutes" in messages[0])

dead = dict(calm, tickets=dict(calm["tickets"], dead_claim=["B-2"]))
messages, state, _, _ = sweep.decide(dead, {}, NOW, "active")
check("one sweep of a dead claim is quiet", messages == [])
messages, state, _, _ = sweep.decide(dead, state, NOW, "active")
check("two sweeps of a dead claim told", len(messages) == 1 and "two sweeps" in messages[0])

idle = summarise(snapshot(waiting=0, claimed=False))
messages, state, _, _ = sweep.decide(idle, {}, NOW, "active")
check("one idle sweep is quiet", messages == [])
messages, state, _, _ = sweep.decide(idle, state, NOW, "active")
check("two idle sweeps told", len(messages) == 1 and "claimed" in messages[0])

# The old noisy kinds never notify on their own.
noisy = dict(calm, tickets=dict(calm["tickets"], needs_host=["B-5"], stale=["B-6"], review_stuck=["B-7"], branch_unlanded_closed=["B-8"], run_again=["B-9"]))
messages, _, _, _ = sweep.decide(noisy, {}, NOW, "active")
check("needs_host, stale, review and branch counts stay silent", messages == [])

if failures:
    sys.exit(f"{len(failures)} failed")
print("all passed")
