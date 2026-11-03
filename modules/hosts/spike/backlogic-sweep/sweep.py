"""Read-only sweep of Aaron's backlogic: counts broken, parked and stale tickets and
work left on origin's ticket branches, for node_exporter and a DM to Aaron.

It changes no ticket: the runner already releases, re-queues and hands on broken
sessions itself (backlogic's docs/decisions/cloud-sessions.md), so this only shows
what that leaves for Aaron.

  sweep.py sweep   as backlogic-runner: writes summary.json and the .prom file
  sweep.py notify  as root: DMs Aaron, through butler-notify, the items newly needing him
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
SEEN = os.environ.get("SWEEP_SEEN", "/var/lib/backlogic-sweep-notify/seen.json")
RUNNER_USER = "backlogic-runner"

HOUR = dt.timedelta(hours=1)
STALE = dt.timedelta(days=14)
REVIEW_STUCK = dt.timedelta(hours=24)
CLOSED = {"done", "archived"}
RUN_AGAIN = "run it again?"
TICKET_BRANCH = re.compile(r"^ticket-(B-[0-9]+)$")
TICKET_ID = re.compile(r"^[A-Z]+-[0-9]+$")

# What each kind counts, in the order the DM and the metrics name them.
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
NEEDS_AARON = ["dead_claim", "run_again", "review_stuck", "branch_unlanded_closed"]


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
    found = {kind: set() for kind in KINDS}
    for request in snap.get("requests", []):
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
        if ticket.get("openRequests", 0) > 0 or ticket["state"] == "waiting":
            found["waiting_on_aaron"].add(tid)
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
    return found, open_by_project, project_of


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
    found, open_by_project, project_of = classify(snap, ahead, landed)
    ran_at = dt.datetime.now(dt.timezone.utc)
    write_prom(found, open_by_project, project_of, ran_at)
    summary = {
        "ranAt": ran_at.isoformat(),
        "open": sum(open_by_project.values()),
        "openByProject": open_by_project,
        "tickets": {kind: sorted(ids) for kind, ids in found.items()},
    }
    with open(os.path.join(STATE, "summary.json.tmp"), "w") as handle:
        json.dump(summary, handle, indent=1)
    os.replace(os.path.join(STATE, "summary.json.tmp"), os.path.join(STATE, "summary.json"))
    counts = ", ".join(f"{kind} {len(ids)}" for kind, ids in found.items())
    print(f"open {summary['open']}: {counts}")


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


def notify():
    summary = read_summary()
    try:
        with open(SEEN) as handle:
            seen = {kind: set(ids) for kind, ids in json.load(handle).items()}
    except (FileNotFoundError, ValueError):
        seen = {}
    new = {kind: [t for t in ids_of(summary, kind) if t not in seen.get(kind, set())] for kind in NEEDS_AARON}
    if any(new.values()):
        parts = []
        for kind, ids in new.items():
            if ids:
                shown = ", ".join(ids[:8]) + (f" and {len(ids) - 8} more" if len(ids) > 8 else "")
                parts.append(f"{len(ids)} {KINDS[kind]} ({shown})")
        opened = summary.get("open")
        opened = opened if isinstance(opened, int) else "?"
        text = (
            f"Backlogic sweep: {sum(map(len, new.values()))} tickets newly need you: "
            + "; ".join(parts)
            + f". Now {opened} open, {count(summary, 'claimed')} claimed, "
            + f"{count(summary, 'needs_host')} parked for the host, {count(summary, 'stale')} stale over 14 days."
        )
        subprocess.run(["butler-notify"], input=text, text=True, check=True, stdout=subprocess.DEVNULL)
    with open(SEEN + ".tmp", "w") as handle:
        json.dump({kind: ids_of(summary, kind) for kind in NEEDS_AARON}, handle)
    os.replace(SEEN + ".tmp", SEEN)


if __name__ == "__main__":
    {"sweep": sweep, "notify": notify}[sys.argv[1]]()
