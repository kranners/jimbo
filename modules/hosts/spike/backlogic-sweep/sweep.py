"""Read-only sweep of Aaron's backlogic: counts broken, parked and stale tickets and
work left on origin's ticket branches, for node_exporter, and tells Aaron only when
backlogic's runner is down or a pile of tickets has waited on him for days.

It changes no ticket: the runner already releases, re-queues and hands on broken
sessions itself (backlogic's docs/decisions/cloud-sessions.md), so this only shows
what that leaves for Aaron.

  sweep.py sweep   as backlogic-runner: writes summary.json and the .prom file
  sweep.py notify  as root: DMs Aaron, through butler-notify, when the runner goes down or
                   comes back, and at most daily when enough tickets have waited on him for days
  sweep.py notify --dry-run  prints what notify would send, changing no state
"""

import datetime as dt
import json
import os
import re
import stat
import subprocess
import sys
import urllib.request

API = "http://127.0.0.1:4200"
REPO = "https://github.com/backlogic/backlogic"
STATE = os.environ.get("SWEEP_STATE", "/var/lib/backlogic-sweep")
TOKEN = os.environ.get("SWEEP_TOKEN_FILE", "/var/lib/backlogic-runner/runner.token")
PROM = os.environ.get("SWEEP_PROM", "/var/lib/claude-limits/backlogic-sweep.prom")
STATE_FILE = os.environ.get("SWEEP_NOTIFY_STATE", "/var/lib/backlogic-sweep-notify/state.json")
RUNNER_USER = os.environ.get("SWEEP_RUNNER_USER", "backlogic-runner")
RUNNER_UNIT = os.environ.get("SWEEP_RUNNER_UNIT", "backlogic-runner-aaron.service")
TICKET_URL = os.environ.get("SWEEP_TICKET_URL", "https://backlogic.spike.cute.engineer/#{id}")
WAITING_AGE = dt.timedelta(days=int(os.environ.get("SWEEP_WAITING_DAYS", "3")))
WAITING_COUNT = int(os.environ.get("SWEEP_WAITING_COUNT", "10"))

HOUR = dt.timedelta(hours=1)
STALE = dt.timedelta(days=14)
REVIEW_STUCK = dt.timedelta(hours=24)
HEARTBEAT_STALE = dt.timedelta(minutes=15)
DAY = dt.timedelta(hours=24)
CLOSED = {"done", "archived"}
RUN_AGAIN = "run it again?"
TICKET_BRANCH = re.compile(r"^ticket-(B-[0-9]+)$")
TICKET_ID = re.compile(r"^[A-Z]+-[0-9]+$")

# What each kind counts, in the order the metrics name them.
KINDS = {
    "claimed": "claimed by a session",
    "dead_claim": "held by a session silent past its hold, which the instance's own sweep should have released",
    "needs_host": "parked for the host after a cloud session broke on it",
    "run_again": "asking Aaron whether to run a silently stopped session again",
    "review_stuck": "pushed for review or landing a day ago with nothing on it since",
    "waiting_on_aaron": "with a question open to Aaron",
    "stale": "open with nothing on it for 14 days",
    "branch_waiting": "open, unclaimed, with work on its branch the next session picks up",
    "branch_unlanded_closed": "closed while its branch still holds work main never took",
}
# Each request's time, under whichever of these names the instance gives it.
REQUEST_TIME = ("askedAt", "createdAt", "openedAt", "at")
RECOVERED = {
    "service": "its service is running again.",
    "heartbeat": "its sessions are sending heartbeats again.",
    "dead_claim": "no ticket is held by a silent session any more.",
    "idle": "sessions are claiming tickets again.",
}


def when(text):
    return dt.datetime.fromisoformat(text.replace("Z", "+00:00"))


def snapshot():
    with open(TOKEN) as handle:
        token = handle.read().strip()
    request = urllib.request.Request(
        f"{API}/api/snapshot", headers={"Authorization": f"Bearer {token}"}
    )
    with urllib.request.urlopen(request, timeout=120) as answer:
        return json.load(answer)


def git(*args, cwd=None):
    return subprocess.run(
        ["git", *args], cwd=cwd, check=True, capture_output=True, text=True
    ).stdout


def ticket_branches():
    """Each ticket branch on origin with commits main has no copy of, by ticket id,
    and the ticket ids main's CHANGELOG names."""
    mirror = os.path.join(STATE, "backlogic.git")
    if not os.path.isdir(mirror):
        git("clone", "--quiet", "--mirror", REPO, mirror)
    else:
        git("fetch", "--quiet", "--prune", "origin", cwd=mirror)
    main = git("symbolic-ref", "--short", "HEAD", cwd=mirror).strip()
    landed = set(re.findall(r"\bB-[0-9]+\b", git("show", f"{main}:CHANGELOG.md", cwd=mirror)))
    ahead = {}
    for ref in git("for-each-ref", "--format=%(refname:short)", "refs/heads/", cwd=mirror).split():
        match = TICKET_BRANCH.match(ref)
        if not match:
            continue
        unique = [line for line in git("cherry", main, ref, cwd=mirror).splitlines() if line.startswith("+")]
        if unique:
            ahead[match.group(1)] = len(unique)
    return ahead, landed


def classify(snap, ahead, landed):
    now = when(snap["now"])
    tickets = {t["id"]: t for t in snap["tickets"]}
    waiting = []
    runner = {"liveClaims": 0, "newestHeartbeat": None, "claimable": 0}
    found = {kind: set() for kind in KINDS}
    asked = {}
    for request in snap.get("requests", []):
        if not request.get("answeredAt") and not request.get("withdrawnAt"):
            stamp = next((request[k] for k in REQUEST_TIME if isinstance(request.get(k), str)), None)
            if stamp and (request["ticket"] not in asked or when(stamp) < when(asked[request["ticket"]])):
                asked[request["ticket"]] = stamp
        if (
            request.get("question", "").endswith(RUN_AGAIN)
            and not request.get("answeredAt")
            and not request.get("withdrawnAt")
            and tickets.get(request["ticket"], {}).get("state") not in CLOSED
        ):
            found["run_again"].add(request["ticket"])
    for ticket in tickets.values():
        if ticket["state"] in CLOSED:
            continue
        tid, claim = ticket["id"], ticket.get("claim")
        moved = when(ticket["movedAt"])
        if claim:
            found["claimed"].add(tid)
            hold = 24 * HOUR if claim.get("turnEnded") == "waiting" else HOUR
            parked = claim.get("usageUntil") and when(claim["usageUntil"]) > now
            if not claim.get("heldOn") and not parked and claim.get("turnEnded") != "waiting":
                runner["liveClaims"] += 1
                beat = claim["heartbeatAt"]
                if runner["newestHeartbeat"] is None or when(beat) > when(runner["newestHeartbeat"]):
                    runner["newestHeartbeat"] = beat
            if not claim.get("heldOn") and not parked and now - when(claim["heartbeatAt"]) > hold:
                found["dead_claim"].add(tid)
        if "needs-host" in ticket.get("tags", []):
            found["needs_host"].add(tid)
        if (
            (ticket.get("isPushedForReview") or ticket.get("isReviewedToLand"))
            and not claim
            and now - moved > REVIEW_STUCK
        ):
            found["review_stuck"].add(tid)
        waits = ticket.get("openRequests", 0) > 0 or ticket["state"] == "waiting"
        if waits:
            found["waiting_on_aaron"].add(tid)
            waiting.append(
                {
                    "id": tid,
                    "since": asked.get(tid, ticket["movedAt"]),
                    "byRequest": tid in asked,
                    "title": ticket.get("title", ""),
                }
            )
        elif (
            not claim
            and "needs-host" not in ticket.get("tags", [])
            and ticket.get("assignee") != "owner"
        ):
            runner["claimable"] += 1
        if now - moved > STALE:
            found["stale"].add(tid)
        if tid in ahead and not claim:
            found["branch_waiting"].add(tid)
    for tid in ahead:
        ticket = tickets.get(tid)
        if (ticket is None or ticket["state"] in CLOSED) and tid not in landed:
            found["branch_unlanded_closed"].add(tid)
    open_by_project = {}
    project_of = {}
    for ticket in tickets.values():
        project_of[ticket["id"]] = ticket.get("project", "unknown")
        if ticket["state"] not in CLOSED:
            open_by_project[ticket["project"]] = open_by_project.get(ticket["project"], 0) + 1
    return found, open_by_project, project_of, waiting, runner


def prom_label(text):
    return text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", " ")


def write_prom(found, open_by_project, project_of, ran_at):
    lines = [
        "# HELP backlogic_sweep_open_tickets Open backlogic tickets by project.",
        "# TYPE backlogic_sweep_open_tickets gauge",
    ]
    for project, count in sorted(open_by_project.items()):
        lines.append(f'backlogic_sweep_open_tickets{{project="{prom_label(project)}"}} {count}')
    lines += [
        "# HELP backlogic_sweep_tickets Backlogic tickets the read-only sweep found, by kind and project.",
        "# TYPE backlogic_sweep_tickets gauge",
    ]
    for kind, ids in found.items():
        by_project = {}
        for tid in ids:
            project = project_of.get(tid, "backlogic")
            by_project[project] = by_project.get(project, 0) + 1
        lines.append(f'backlogic_sweep_tickets{{kind="{kind}",project="all"}} {len(ids)}')
        for project, count in sorted(by_project.items()):
            lines.append(f'backlogic_sweep_tickets{{kind="{kind}",project="{prom_label(project)}"}} {count}')
    lines += [
        "# HELP backlogic_sweep_last_run_seconds When the sweep last finished.",
        "# TYPE backlogic_sweep_last_run_seconds gauge",
        f"backlogic_sweep_last_run_seconds {int(ran_at.timestamp())}",
    ]
    with open(PROM + ".tmp", "w") as handle:
        handle.write("\n".join(lines) + "\n")
    os.replace(PROM + ".tmp", PROM)


def sweep():
    snap = snapshot()
    ahead, landed = ticket_branches()
    found, open_by_project, project_of, waiting, runner = classify(snap, ahead, landed)
    ran_at = dt.datetime.now(dt.timezone.utc)
    write_prom(found, open_by_project, project_of, ran_at)
    summary = {
        "ranAt": ran_at.isoformat(),
        "open": sum(open_by_project.values()),
        "openByProject": open_by_project,
        "tickets": {kind: sorted(ids) for kind, ids in found.items()},
        "waiting": sorted(waiting, key=lambda item: when(item["since"])),
        "runner": runner,
    }
    with open(os.path.join(STATE, "summary.json.tmp"), "w") as handle:
        json.dump(summary, handle, indent=1)
    os.replace(os.path.join(STATE, "summary.json.tmp"), os.path.join(STATE, "summary.json"))
    counts = ", ".join(f"{kind} {len(ids)}" for kind, ids in found.items())
    print(f"open {summary['open']}: {counts}")
    now = when(snap["now"])
    old = [item for item in waiting if now - when(item["since"]) >= WAITING_AGE]
    oldest = max((now - when(item["since"]) for item in waiting), default=dt.timedelta())
    fields = sorted({key for request in snap.get("requests", []) for key in request})
    print(
        f"waiting on Aaron: {len(waiting)}, {len(old)} over {WAITING_AGE.days} days, oldest {oldest.days} days "
        f"({sum(1 for item in waiting if item['byRequest'])} timed by their request, request fields {','.join(fields)}); "
        f"runner: {runner['liveClaims']} live claims, newest heartbeat {runner['newestHeartbeat']}, {runner['claimable']} claimable"
    )


def read_summary():
    """The sweep's summary, refusing anything but a regular file the runner's user owns,
    since its sessions could plant a link there for root to follow."""
    import pwd

    fd = os.open(os.path.join(STATE, "summary.json"), os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(fd) as handle:
        info = os.fstat(handle.fileno())
        if not stat.S_ISREG(info.st_mode) or info.st_uid != pwd.getpwnam(RUNNER_USER).pw_uid:
            raise SystemExit("summary.json is not the runner's own file")
        if info.st_size > 4_000_000:
            raise SystemExit("summary.json is too large")
        return json.load(handle)


def ids_of(summary, kind):
    """Only ticket ids pass from the runner's file into the DM, never its text."""
    ids = summary.get("tickets", {}).get(kind, [])
    return sorted({t for t in ids if isinstance(t, str) and TICKET_ID.match(t)})


def count(summary, kind):
    return len(ids_of(summary, kind))


def since_of(text):
    """A timestamp from the runner's file, or None when it is not one."""
    try:
        moment = when(text)
    except (TypeError, ValueError, AttributeError):
        return None
    return moment if moment.tzinfo else None


def clean_title(text):
    """A ticket title fit for one line of Aaron's DM: printable, no markup, short."""
    if not isinstance(text, str):
        return ""
    text = "".join(c if c.isprintable() else " " for c in text)
    text = re.sub(r"[<>@`*_|~\[\]]", "", text)
    text = " ".join(text.split())
    return text[:80] + ("…" if len(text) > 80 else "")


def plural(n, word):
    return f"{n} {word}" + ("" if n == 1 else "s")


RESTART = "restart it on spike with `sudo systemctl restart backlogic-runner-aaron`"


def runner_problems(summary, previous, now, runner_active):
    """What is down about backlogic's runner now, by key, each saying what and the one thing to do."""
    problems = {}
    if runner_active != "active":
        problems["service"] = f"backlogic's runner service is {runner_active}, so no ticket is being worked; {RESTART}."
    runner = summary.get("runner") if isinstance(summary.get("runner"), dict) else {}
    live = runner.get("liveClaims") if isinstance(runner.get("liveClaims"), int) else 0
    newest = since_of(runner.get("newestHeartbeat"))
    if live and newest and now - newest > HEARTBEAT_STALE:
        minutes = int((now - newest).total_seconds() // 60)
        problems["heartbeat"] = (
            f"none of the runner's {plural(live, 'working session')} has sent a heartbeat for {minutes} minutes; {RESTART}."
        )
    dead = count(summary, "dead_claim")
    if dead and previous.get("dead_claim", 0):
        problems["dead_claim"] = (
            f"{plural(dead, 'ticket')} stayed claimed by a silent session for two sweeps, which the runner should have released; {RESTART}."
        )
    claimed = count(summary, "claimed")
    claimable = runner.get("claimable") if isinstance(runner.get("claimable"), int) else 0
    if not claimed and claimable and previous.get("claimed", 1) == 0 and previous.get("claimable", 0):
        problems["idle"] = (
            f"no session has claimed any of {plural(claimable, 'queued ticket')} for two sweeps, so its lanes are stuck "
            "or every account is at its limit; check the accounts' usage, then restart the runner."
        )
    return problems


def waiting_notice(summary, now):
    """The daily notice of tickets waiting on Aaron for days, or None below the threshold."""
    waiting = []
    for item in summary.get("waiting", []):
        if not isinstance(item, dict) or not TICKET_ID.match(str(item.get("id", ""))):
            continue
        since = since_of(item.get("since"))
        if since and now - since >= WAITING_AGE:
            waiting.append((since, item["id"], clean_title(item.get("title"))))
    if len(waiting) < WAITING_COUNT:
        return None, len(waiting)
    waiting.sort()
    days = lambda since: int((now - since).total_seconds() // 86400)
    lines = [
        f"Backlogic: {len(waiting)} tickets have waited on you for over {plural(WAITING_AGE.days, 'day')}, "
        f"the oldest {plural(days(waiting[0][0]), 'day')}. The oldest three:"
    ]
    for since, tid, title in waiting[:3]:
        lines.append(f"- {tid}, {plural(days(since), 'day')}: {title or 'untitled'} {TICKET_URL.format(id=tid)}")
    return "\n".join(lines), len(waiting)


def decide(summary, state, now, runner_active):
    """The notices one run sends and the state it leaves, from the sweep's summary and the last state.
    A missing state seeds silently, so the deploy that brings this in sends nothing."""
    seeding = state is None
    state = state or {}
    previous = state.get("previous", {})
    down = dict(state.get("down", {}))
    clearing = dict(state.get("clearing", {}))
    problems = runner_problems(summary, previous, now, runner_active)
    went_down = [text for key, text in problems.items() if key not in down]
    recovered = []
    for key in list(down):
        if key in problems:
            clearing.pop(key, None)
            continue
        # A problem counts as gone only once two sweeps in a row have not seen it, so one that flaps is told once.
        clearing[key] = clearing.get(key, 0) + 1
        if clearing[key] >= 2:
            recovered.append(RECOVERED.get(key, "backlogic's runner is working again."))
            del down[key], clearing[key]
    for key, text in problems.items():
        down.setdefault(key, text)
    messages = []
    if went_down:
        messages.append("Backlogic's runner is down: " + " ".join(went_down))
    if recovered:
        messages.append("Backlogic's runner is back: " + " ".join(recovered))
    last = since_of(state.get("waitingNotifiedAt"))
    waiting, old = waiting_notice(summary, now)
    waiting_at = state.get("waitingNotifiedAt")
    if waiting and (last is None or now - last >= DAY):
        messages.append(waiting)
        waiting_at = now.isoformat()
    new_state = {
        "down": down,
        "clearing": clearing,
        "waitingNotifiedAt": waiting_at,
        "previous": {
            "claimed": count(summary, "claimed"),
            "dead_claim": count(summary, "dead_claim"),
            "claimable": (summary.get("runner") or {}).get("claimable", 0) if isinstance(summary.get("runner"), dict) else 0,
        },
    }
    log = (
        f"runner {runner_active}, down: {', '.join(sorted(down)) or 'nothing'}; "
        f"{old} waiting on Aaron over {plural(WAITING_AGE.days, 'day')} (notice at {WAITING_COUNT})"
    )
    return messages, new_state, log, seeding


def notify(dry_run=False):
    summary = read_summary()
    try:
        with open(STATE_FILE) as handle:
            state = json.load(handle)
        if not isinstance(state, dict):
            state = None
    except (FileNotFoundError, ValueError):
        state = None
    runner_active = subprocess.run(
        ["systemctl", "is-active", RUNNER_UNIT], capture_output=True, text=True
    ).stdout.strip() or "unknown"
    now = dt.datetime.now(dt.timezone.utc)
    messages, new_state, log, seeding = decide(summary, state, now, runner_active)
    print(f"notify: {log}")
    if seeding:
        print("notify: first run, seeded silently" + ("; it would have sent:" if messages else ", nothing to send"))
    for text in messages:
        if seeding or dry_run:
            print(("would send: " if dry_run else "") + text)
        else:
            subprocess.run(["butler-notify"], input=text, text=True, check=True, stdout=subprocess.DEVNULL)
            print(f"sent: {text.splitlines()[0]}")
    if not messages and not seeding:
        print("notify: nothing to send")
    if not dry_run:
        with open(STATE_FILE + ".tmp", "w") as handle:
            json.dump(new_state, handle)
        os.replace(STATE_FILE + ".tmp", STATE_FILE)


if __name__ == "__main__":
    if sys.argv[1] == "sweep":
        sweep()
    elif sys.argv[1] == "notify":
        notify(dry_run="--dry-run" in sys.argv[2:])
    else:
        raise SystemExit("usage: sweep.py sweep | notify [--dry-run]")
