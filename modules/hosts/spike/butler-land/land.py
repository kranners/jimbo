"""butler's landing queue on spike.

A deploy that would restart butler, or the speech services its calls use,
waits here while Aaron is on a call, and goes out on a cue: Aaron's word, a
quiet moment in the call, a time he named, the call ending, or a maximum hold.

Deploys reach it through `gate`, from jimbo-switch and butler-pull, which
either go on at once or leave a held entry in the queue.  While the queue
holds anything, `watch`, run by a systemd path unit as root, checks the cues
every few seconds, gives the shout, marks the entry released and starts the
deploy's own unit again, whose `gate` then lets it through.

Aaron and butler steer it with `status`, `now`, `hold`, `release`,
`when-quiet`, `at HH:MM`, `on`, `off` and `always`, from `/land` or the
`land-queue` command.

Its state lives in one directory, `LAND_STATE`: `settings.json` (the mode and
Aaron's cues), `queue.json` (present only while something is held) and
`log.jsonl` (every hold and release, with its reason).  The daemon's call
state file, `LAND_CALL_STATE`, says whether a call is live and how long it
has been quiet, and its `turns`, live call or not, which turns are running
and since when, so a landing that restarts butler also waits, at most
TURN_HOLD_S, while a turn under TURN_YOUNG_S old is in flight.
"""

import fcntl
import json
import os
import subprocess
import sys
import time
from contextlib import contextmanager

STATE = os.environ.get("LAND_STATE", "/var/lib/butler-land")
CALL_STATE = os.environ.get("LAND_CALL_STATE", "/run/butler-call/call.json")
QUIET_S = int(os.environ.get("LAND_QUIET_S", "20"))
MAX_HOLD_S = int(os.environ.get("LAND_MAX_HOLD_S", "1800"))
# A call state older than this means the daemon is not writing it: no call is live.
STALE_S = int(os.environ.get("LAND_STALE_S", "20"))
# How long Aaron must have been silent for a release not to cut him off mid-sentence.
SENTENCE_S = float(os.environ.get("LAND_SENTENCE_S", "1.5"))
# How long to wait after the shout for butler to finish saying it and Aaron to stop talking.
CUE_WAIT_S = float(os.environ.get("LAND_CUE_WAIT_S", "20"))
# A deploy that restarts butler waits while a turn younger than this runs, since it may well finish soon.
TURN_YOUNG_S = int(os.environ.get("LAND_TURN_YOUNG_S", str(20 * 60)))
# The longest that wait for a running turn holds a landing.
TURN_HOLD_S = int(os.environ.get("LAND_TURN_HOLD_S", str(10 * 60)))
POLL_S = float(os.environ.get("LAND_POLL_S", "5"))
# How long `now` with nothing waiting marks the next landing urgent.
NOW_WINDOW_S = 15 * 60
SAY = os.environ.get("LAND_SAY", "butler-call-say")
NOTIFY = os.environ.get("LAND_NOTIFY", "butler-notify")
# Starts a repository's deploy unit again once its entry is released.
START = os.environ.get("LAND_START", "systemctl start --no-block").split()
UNITS = {
    "jimbo": "jimbo-switch.service",
    "claude-discord-threads": "butler-pull.service",
}
# Units whose restart a switch defers to the daemon's own quiet moment, which says its own line.
DEFERRED = set(os.environ.get("LAND_DEFERRED", "butler.service").split())
CUE_LINE = "A change is about to land, sir, I'll be back in a moment."
MODES = {
    "call": "on: deploys that would restart butler wait while a call is live",
    "off": "off: every deploy goes out at once",
    "always": "always: deploys that would restart butler wait for a cue even with no call",
}

os.umask(0o007)


def now():
    return time.time()


def log(event, **fields):
    record = {"at": round(now(), 3), "event": event, **fields}
    print(json.dumps(record), file=sys.stderr)
    path = os.path.join(STATE, "log.jsonl")
    try:
        if os.path.exists(path) and os.path.getsize(path) > 1_000_000:
            os.replace(path, f"{path}.1")
        with open(path, "a") as f:
            f.write(json.dumps(record) + "\n")
    except OSError as err:
        print(f"butler-land: could not write the log: {err}", file=sys.stderr)


@contextmanager
def locked():
    with open(os.path.join(STATE, "lock"), "a") as f:
        fcntl.flock(f, fcntl.LOCK_EX)
        try:
            yield
        finally:
            fcntl.flock(f, fcntl.LOCK_UN)


def read_json(name, default):
    try:
        with open(os.path.join(STATE, name)) as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def write_json(name, value):
    path = os.path.join(STATE, name)
    tmp = f"{path}.tmp.{os.getpid()}"
    with open(tmp, "w") as f:
        json.dump(value, f, indent=1)
    os.chmod(tmp, 0o660)
    os.replace(tmp, path)


def settings():
    s = read_json("settings.json", {})
    s.setdefault("mode", "call")
    if s["mode"] not in MODES:
        s["mode"] = "call"
    return s


def queue():
    return read_json("queue.json", {})


def save_queue(q):
    if q:
        write_json("queue.json", q)
    else:
        try:
            os.remove(os.path.join(STATE, "queue.json"))
        except FileNotFoundError:
            pass


def call_state(at=None):
    """The live call, or None: the daemon's file, trusted only while fresh."""
    at = now() if at is None else at
    try:
        with open(CALL_STATE) as f:
            c = json.load(f)
    except (OSError, ValueError):
        return None
    if not c.get("live") or at - c.get("updatedAt", 0) / 1000 > STALE_S:
        return None
    return c


def turns_state(at=None):
    """The daemon's turn pool, or None: from the same file, trusted only while fresh, call or not."""
    at = now() if at is None else at
    try:
        with open(CALL_STATE) as f:
            c = json.load(f)
    except (OSError, ValueError):
        return None
    if at - c.get("updatedAt", 0) / 1000 > STALE_S or not isinstance(c.get("turns"), dict):
        return None
    return c["turns"]


def young_turns(turns, at):
    """How many running turns started under TURN_YOUNG_S ago."""
    if not turns:
        return 0
    return sum(1 for started in turns.get("runningStartedAt") or [] if at - started / 1000 < TURN_YOUNG_S)


def quiet_for(call, at):
    """Seconds the call has had no speech, audio or work, or 0 while it has any."""
    if any(call.get(k) for k in ("callerSpeaking", "butlerSpeaking", "audioPlaying", "working")):
        return 0
    return max(0, at - (call.get("lastActiveAt") or 0) / 1000)


def clock(t):
    return time.strftime("%H:%M", time.localtime(t))


def decide(entry, s, call, at, turns=None):
    """Whether a held entry goes now, and why: (go, reason)."""
    if s["mode"] == "off":
        return True, "the landing queue is off"
    if entry.get("urgent"):
        return True, f"it is urgent: {entry['urgent']}"
    if s.get("nowUntil") and at <= s["nowUntil"]:
        return True, "Aaron asked to land now"
    if s.get("at") and at >= s["at"]:
        return True, f"it is {clock(s['at'])}, the time Aaron set"
    later = s.get("at") and s["at"] > at
    if not later and at - entry["heldSince"] >= MAX_HOLD_S:
        return True, f"it has waited the longest hold, {MAX_HOLD_S // 60} minutes"
    if s.get("hold"):
        return False, "Aaron is holding landings"
    if later:
        return False, f"waiting until {clock(s['at'])}"
    young = young_turns(turns, at) if "butler.service" in entry.get("restarts", []) else 0
    if young and at - entry["heldSince"] < TURN_HOLD_S:
        return False, f"waiting for {young} turn{'s' if young != 1 else ''} butler is working on to finish, at most {TURN_HOLD_S // 60} minutes"
    if call is None:
        if s["mode"] == "always":
            return False, "always holding, until Aaron lands it, a set time or the longest hold"
        return True, "no call is live"
    q = quiet_for(call, at)
    if q >= QUIET_S:
        return True, f"the call has been quiet for {int(q)} seconds"
    return False, "waiting for a quiet moment in the call"


def run(argv, stdin=None):
    try:
        r = subprocess.run(argv, input=stdin or "", capture_output=True, text=True, timeout=30)
        return r.returncode, (r.stdout + r.stderr).strip()
    except (OSError, subprocess.TimeoutExpired) as err:
        return 1, str(err)


def mid_sentence(at=None):
    at = now() if at is None else at
    call = call_state(at)
    if call is None:
        return False
    if call.get("callerSpeaking"):
        return True
    last = call.get("lastCallerAt")
    return last is not None and at - last / 1000 < SENTENCE_S


def cue(entry):
    """Tells Aaron a held landing goes now, and waits so it never cuts in: True once it may go."""
    if call_state() is None:
        n = len(entry["commits"])
        run([NOTIFY], f"Landing {n} fix{'es' if n != 1 else ''} held back for your call or a running turn now; butler restarts for a moment.")
        return True
    # butler defers its own restart to a quiet moment and announces it, so only a speech service restarted at once needs this shout.
    direct = [u for u in entry.get("restarts", []) if u not in DEFERRED]
    if direct and now() - entry.get("cuedAt", 0) > 120:
        code, out = run([SAY, "--urgent", "--call-only"], CUE_LINE)
        log("cue", repo=entry["repo"], to=entry["to"], spoken=code == 0, said=out)
        entry["cuedAt"] = now()
    until = time.monotonic() + CUE_WAIT_S
    while time.monotonic() < until:
        call = call_state()
        if call is None or (not call.get("butlerSpeaking") and not mid_sentence()):
            return True
        time.sleep(0.5)
    return False


def summary(entry):
    return [f"{c['hash'][:7]} {c['subject']}" for c in entry["commits"]][:20]


# Commands from jimbo-switch and butler-pull.


def read_commits(path):
    commits = []
    with open(path) as f:
        for line in f:
            parts = line.rstrip("\n").split("\t", 2)
            if len(parts) == 3:
                commits.append({"hash": parts[0], "at": int(parts[1]), "subject": parts[2][:200]})
    return commits


def gate(args):
    """gate <repo> <from> <to> <commits file> <restarts> [urgent reason]: exit 0 to deploy, 3 to hold."""
    repo, frm, to, commits_file, restarts = args[:5]
    urgent = args[5] if len(args) > 5 and args[5] else None
    restarts = restarts.split()
    at = now()
    with locked():
        q = queue()
        entry = q.get(repo)
        if entry and entry.get("released"):
            del q[repo]
            save_queue(q)
            log("deploy", repo=repo, to=to, reason=entry.get("releasedBecause", "released"))
            print(f"go: released, {entry.get('releasedBecause', '')}")
            return 0
        if not restarts:
            if entry:
                del q[repo]
                save_queue(q)
            print("go: it restarts nothing a call needs")
            return 0
        fresh = {
            "repo": repo,
            "from": frm,
            "to": to,
            "commits": read_commits(commits_file),
            "restarts": restarts,
            "heldSince": entry["heldSince"] if entry else at,
            **({"urgent": urgent} if urgent else {}),
            **({"cuedAt": entry["cuedAt"]} if entry and "cuedAt" in entry else {}),
        }
        s = settings()
        go, reason = decide(fresh, s, call_state(at), at, turns_state(at))
        if go and (not entry or urgent):
            if entry:
                del q[repo]
                save_queue(q)
            log("deploy", repo=repo, to=to, restarts=restarts, reason=reason)
            print(f"go: {reason}")
            go_now = True
        else:
            go_now = False
    if go_now:
        # An urgent landing during a call still gets the shout, without waiting for a quiet moment.
        if urgent and call_state() is not None:
            cue(fresh)
        return 0
    with locked():
        q = queue()
        entry = q.get(repo)
        if entry and entry.get("to") == to and not urgent:
            # Held already: the watcher decides when, and gives the cue.
            print(f"held: {reason}")
            return 3
        q[repo] = fresh
        save_queue(q)
        log("hold", repo=repo, to=to, restarts=restarts, commits=summary(fresh), reason=reason)
        print(f"held: {reason}")
        return 3


def landed(args):
    repo, to = args[:2]
    with locked():
        q = queue()
        q.pop(repo, None)
        save_queue(q)
        s = settings()
        if not q and s.get("nowUntil") and s.get("nowFor") == "queue":
            s.pop("nowUntil", None)
            s.pop("nowFor", None)
            write_json("settings.json", s)
    log("landed", repo=repo, to=to)
    return 0


def failed(args):
    """failed <repo> <to> <stage> <subject>: logs it and tells Aaron, so a hold never hides a broken commit."""
    repo, to, stage, subject = (args + ["", "", "", ""])[:4]
    log("failed", repo=repo, to=to, stage=stage, subject=subject)
    line = f"A landed fix failed to {stage} on spike, so it stays on the last good version: {subject}"
    line = " ".join(line.replace("http://", "").replace("https://", "").split())[:200]
    code, out = run([SAY], line)
    if code != 0:
        print(f"butler-land: could not tell Aaron: {out}", file=sys.stderr)
    return 0


def tick():
    """One pass of the watcher: release every held entry whose cue has come."""
    at = now()
    with locked():
        q = queue()
        s = settings()
        if s.get("at") and at > s["at"] and not q:
            s.pop("at", None)
            write_json("settings.json", s)
        due = []
        for repo, entry in q.items():
            if entry.get("released"):
                continue
            go, reason = decide(entry, s, call_state(at), at, turns_state(at))
            if go:
                due.append((repo, reason))
    for repo, reason in due:
        with locked():
            entry = queue().get(repo)
        if not entry or entry.get("released"):
            continue
        if not cue(entry):
            log("wait", repo=repo, to=entry["to"], reason="Aaron or butler is still talking")
            with locked():
                q = queue()
                if repo in q:
                    q[repo]["cuedAt"] = entry.get("cuedAt", 0)
                    save_queue(q)
            continue
        with locked():
            q = queue()
            if repo not in q:
                continue
            q[repo]["released"] = True
            q[repo]["releasedAt"] = now()
            q[repo]["releasedBecause"] = reason
            save_queue(q)
        log("release", repo=repo, to=entry["to"], restarts=entry["restarts"], commits=summary(entry), reason=reason)
        code, out = run(START + [UNITS.get(repo, repo)])
        if code != 0:
            log("release-failed", repo=repo, error=out)


def watch(args):
    """Runs while anything is held, checking the cues every few seconds."""
    passes = int(args[0]) if args else -1
    while os.path.exists(os.path.join(STATE, "queue.json")) and passes != 0:
        tick()
        q = queue()
        if q and all(e.get("released") for e in q.values()):
            # Released and waiting on its unit, which removes the entry as it deploys.
            stuck = [r for r, e in q.items() if now() - e.get("releasedAt", e["heldSince"]) > 900]
            if stuck:
                with locked():
                    q = queue()
                    for r in stuck:
                        log("dropped", repo=r, reason="its deploy did not pick it up in 15 minutes")
                        q.pop(r, None)
                    save_queue(q)
        passes -= 1
        if passes != 0:
            time.sleep(POLL_S)
    return 0


# Aaron's commands.


def status():
    at = now()
    s = settings()
    q = queue()
    call = call_state(at)
    lines = [f"Landing queue {MODES[s['mode']]}."]
    if call is None:
        lines.append("No call is live.")
    else:
        q_for = quiet_for(call, at)
        lines.append(f"A call is live, quiet for {int(q_for)} seconds." if q_for else "A call is live and someone is talking or working.")
    if s.get("hold"):
        lines.append("Aaron is holding landings until he releases them.")
    if s.get("at") and s["at"] > at:
        lines.append(f"Held landings go at {clock(s['at'])}.")
    if s.get("nowUntil") and s["nowUntil"] >= at:
        lines.append("The next landing goes out at once." if s.get("nowFor") == "next" else "Everything waiting lands now.")
    if not q:
        lines.append("Nothing is waiting.")
    for repo, entry in sorted(q.items()):
        held = int((at - entry["heldSince"]) // 60)
        state = "released, deploying" if entry.get("released") else decide(entry, s, call, at, turns_state(at))[1]
        latest = entry["heldSince"] + MAX_HOLD_S
        lines.append(f"{repo}: held since {clock(entry['heldSince'])} ({held} min), would restart {', '.join(entry['restarts'])}; {state}.")
        if not entry.get("released") and not (s.get("at") and s["at"] > at):
            lines.append(f"  It lands by {clock(latest)} at the latest.")
        for c in entry["commits"][:10]:
            lines.append(f"  - {clock(c['at'])} {c['subject']} ({c['hash'][:7]})")
        if len(entry["commits"]) > 10:
            lines.append(f"  - and {len(entry['commits']) - 10} more")
    return "\n".join(lines)


def parse_time(text, at):
    try:
        h, m = (int(x) for x in text.split(":"))
        if not (0 <= h < 24 and 0 <= m < 60):
            raise ValueError
    except ValueError:
        return None
    t = time.localtime(at)
    target = time.mktime((t.tm_year, t.tm_mon, t.tm_mday, h, m, 0, 0, 0, -1))
    if target <= at:
        target = time.mktime((t.tm_year, t.tm_mon, t.tm_mday + 1, h, m, 0, 0, 0, -1))
    return target


USAGE = "usage: land-queue [status | now | hold | release | when-quiet | at HH:MM | on | off | always]"


def control(args):
    word = args[0].lower() if args else "status"
    at = now()
    with locked():
        s = settings()
        q = queue()
        said = None
        if word in ("status", "queue"):
            pass
        elif word == "now":
            s["nowUntil"] = at + NOW_WINDOW_S
            s["nowFor"] = "queue" if q else "next"
            s.pop("hold", None)
            said = "Landing everything waiting now." if q else "Nothing is waiting; the next landing in the next 15 minutes goes out at once."
        elif word == "hold":
            s["hold"] = True
            said = f"Holding landings that would restart butler until you release them, for at most {MAX_HOLD_S // 60} minutes each."
        elif word in ("release", "when-quiet"):
            for k in ("hold", "at", "nowUntil", "nowFor"):
                s.pop(k, None)
            said = "Released: held landings go at the next quiet moment in a call, or at once with no call."
        elif word == "at":
            target = parse_time(args[1], at) if len(args) > 1 else None
            if target is None:
                return 2, "usage: land-queue at HH:MM (24-hour, Melbourne time)"
            s["at"] = target
            s.pop("hold", None)
            said = f"Held landings go at {clock(target)}{' tomorrow' if time.localtime(target).tm_mday != time.localtime(at).tm_mday else ''}."
        elif word in ("on", "off", "always"):
            s["mode"] = {"on": "call", "off": "off", "always": "always"}[word]
            said = f"Landing queue {MODES[s['mode']]}."
        else:
            return 2, USAGE
        if said:
            write_json("settings.json", s)
    if said:
        log("control", command=" ".join(args), by=os.environ.get("USER", ""))
        return 0, f"{said}\n\n{status()}"
    return 0, status()


def main(argv):
    cmd = argv[1] if len(argv) > 1 else "status"
    rest = argv[2:]
    if cmd == "gate":
        return gate(rest)
    if cmd == "landed":
        return landed(rest)
    if cmd == "failed":
        return failed(rest)
    if cmd == "watch":
        return watch(rest)
    if cmd == "would-hold":
        # Whether a deploy that restarts butler would be held now, so jimbo-switch builds before switching.
        at = now()
        with locked():
            entry = queue().get(rest[0]) if rest else None
        probe = entry or {"repo": "", "commits": [], "restarts": ["butler.service"], "heldSince": at}
        return 3 if entry or not decide(probe, settings(), call_state(at), at, turns_state(at))[0] else 0
    code, out = control(argv[1:])
    print(out)
    return code


if __name__ == "__main__":
    sys.exit(main(sys.argv))
