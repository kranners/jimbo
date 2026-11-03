"""Spike's side of the change probe.

A change's cloud session cannot reach spike, so it leaves signed bash scripts on
the branch spike-probe/<change id> of the private butler-memory repository,
and this runner, polling from spike, runs each in the probe sandbox and pushes
its output back to the same branch. Nothing connects in to spike.

  runner.py key <id>   print the per-fix key the launcher gives that session
  runner.py poll       one pass: fetch, verify, run, record, push

A request is honoured only while its fix is live: its cloud session started,
spike still watches it, and nobody archived it or marked it done. Every request
and result is logged, and each fix may run a limited number an hour.
"""

import hashlib
import hmac
import json
import os
import re
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ID = re.compile(r"^[0-9]{8}-[0-9]{6}-[0-9]+$")
NUMBER = re.compile(r"^[0-9]{1,4}$")

STATE = Path(os.environ.get("PROBE_STATE", "/var/lib/butler-probe-runner"))
SELF_FIX = Path(os.environ.get("PROBE_SELF_FIX", "/var/lib/butler/self-fix"))
KEY_FILE = Path(os.environ.get("PROBE_KEY_FILE", "/var/lib/secrets/butler-probe-key"))
REMOTE = os.environ.get("PROBE_REMOTE", "git@github.com:kranners/butler-memory.git")
# The command a script is handed to on stdin: the probe sandbox's socket on spike.
RUN = json.loads(os.environ.get("PROBE_RUN", '["socat", "-t", "90", "-", "UNIX-CONNECT:/run/butler-probe.sock"]'))
PER_HOUR = int(os.environ.get("PROBE_PER_HOUR", "30"))
PER_POLL = int(os.environ.get("PROBE_PER_POLL", "4"))
MAX_SCRIPT = 16 * 1024
MAX_OUTPUT = 48 * 1024
LIVE_FOR = 2 * 24 * 3600

REPO = STATE / "repo.git"
RESULTS = STATE / "results"
LOG = STATE / "log.jsonl"
PREFIX = "spike-probe/"


def fix_key(fix: str) -> bytes:
    master = bytes.fromhex(KEY_FILE.read_text().strip())
    return hmac.new(master, b"spike-probe:" + fix.encode(), hashlib.sha256).digest()


def signature(key: bytes, fix: str, number: str, script: bytes) -> str:
    return hmac.new(key, f"{fix}\n{number}\n".encode() + script, hashlib.sha256).hexdigest()


def live(fix: str) -> bool:
    """A fix butler started whose cloud session is still running and watched."""
    session = SELF_FIX / "sessions" / fix
    try:
        started = session.read_text().startswith("Started ")
        young = time.time() - session.stat().st_mtime < LIVE_FOR
    except OSError:
        return False
    ended = any((SELF_FIX / d / fix).exists() for d in ("archive", "archived", "dismissed"))
    return started and young and not ended and (SELF_FIX / "watch" / fix).exists()


def git(*args: str, data: bytes | None = None, env: dict | None = None) -> bytes:
    return subprocess.run(
        ["git", "--git-dir", str(REPO), *args],
        input=data,
        capture_output=True,
        check=True,
        env={**os.environ, **(env or {})},
    ).stdout


def log(entry: dict) -> None:
    entry = {"time": time.strftime("%Y-%m-%dT%H:%M:%S%z"), **entry}
    with LOG.open("a") as f:
        f.write(json.dumps(entry) + "\n")
    print(json.dumps(entry), flush=True)


def recent(fix: str) -> int:
    since = time.time() - 3600
    count = 0
    for result in (RESULTS / fix).glob("*.txt"):
        if result.stat().st_mtime > since:
            count += 1
    return count


def run(fix: str, number: str, script: bytes) -> str:
    try:
        done = subprocess.run(RUN, input=script, capture_output=True, timeout=100)
        output = done.stdout + done.stderr
    except subprocess.TimeoutExpired as e:
        output = (e.stdout or b"") + b"\n[spike-probe: stopped after 100 seconds]"
    text = output.decode("utf-8", "replace")
    if len(text) > MAX_OUTPUT:
        text = text[:MAX_OUTPUT] + f"\n[spike-probe: output cut off after {MAX_OUTPUT} characters]"
    return text


def handle(fix: str, ref: str, budget: int) -> int:
    """Runs this fix's new requests, recording each result locally; returns how many ran."""
    names = git("ls-tree", "--name-only", f"{ref}:requests").decode().split() if has(ref, "requests") else []
    numbers = sorted({n[:-3] for n in names if n.endswith(".sh") and NUMBER.match(n[:-3])}, key=int)
    ran = 0
    out = RESULTS / fix
    out.mkdir(parents=True, exist_ok=True)
    key = fix_key(fix)
    for number in numbers:
        if (out / f"{number}.txt").exists():
            continue
        if ran >= budget:
            break
        script = git("cat-file", "blob", f"{ref}:requests/{number}.sh")
        sig = git("cat-file", "blob", f"{ref}:requests/{number}.sig").decode().strip() if has(ref, f"requests/{number}.sig") else ""
        digest = hashlib.sha256(script).hexdigest()
        stamp = time.strftime("%Y-%m-%d %H:%M:%S %Z")
        if len(script) > MAX_SCRIPT:
            status, text = "refused", f"spike-probe refused #{number}: the script is over {MAX_SCRIPT} bytes.\n"
        elif not hmac.compare_digest(sig, signature(key, fix, number, script)):
            status, text = "refused", f"spike-probe refused #{number}: its signature does not match this change's key.\n"
        elif recent(fix) >= PER_HOUR:
            status, text = "refused", f"spike-probe refused #{number}: this change already ran {PER_HOUR} requests in the last hour; wait and send it again as a new request.\n"
        else:
            status = "ran"
            text = f"spike-probe #{number} for change {fix}, run {stamp} on spike as butler-probe:\n" + run(fix, number, script)
            ran += 1
        (out / f"{number}.sh").write_bytes(script)
        (out / f"{number}.txt").write_text(text)
        log({"fix": fix, "request": number, "sha256": digest, "status": status, "bytes": len(text)})
    return ran


def has(ref: str, path: str) -> bool:
    return subprocess.run(
        ["git", "--git-dir", str(REPO), "cat-file", "-e", f"{ref}:{path}"], capture_output=True
    ).returncode == 0


def publish(fix: str, ref: str) -> None:
    """Commits every recorded result the branch lacks on top of it and pushes, retried next poll if the session pushed first."""
    missing = [r for r in sorted((RESULTS / fix).glob("*.txt")) if not has(ref, f"results/{r.name}")]
    if not missing:
        return
    with tempfile.TemporaryDirectory() as tmp:
        env = {
            "GIT_INDEX_FILE": f"{tmp}/index",
            "GIT_AUTHOR_NAME": "spike-probe",
            "GIT_AUTHOR_EMAIL": "spike-probe@spike",
            "GIT_COMMITTER_NAME": "spike-probe",
            "GIT_COMMITTER_EMAIL": "spike-probe@spike",
        }
        git("read-tree", ref, env=env)
        for result in missing:
            blob = git("hash-object", "-w", "--stdin", data=result.read_bytes()).decode().strip()
            git("update-index", "--add", "--cacheinfo", f"100644,{blob},results/{result.name}", env=env)
        tree = git("write-tree", env=env).decode().strip()
        parent = git("rev-parse", ref).decode().strip()
        names = ", ".join(r.stem for r in missing)
        commit = git("commit-tree", tree, "-p", parent, "-m", f"spike-probe results {names}", env=env).decode().strip()
    pushed = subprocess.run(
        ["git", "--git-dir", str(REPO), "push", "--quiet", REMOTE, f"{commit}:refs/heads/{PREFIX}{fix}"],
        capture_output=True,
    )
    if pushed.returncode != 0:
        print(f"spike-probe: could not push results for {fix}, retrying next poll: {pushed.stderr.decode()[-300:]}", file=sys.stderr)


def poll() -> None:
    STATE.mkdir(parents=True, exist_ok=True)
    fixes = sorted(p.name for p in (SELF_FIX / "watch").glob("*") if ID.match(p.name) and live(p.name))
    if not fixes:
        return
    if not REPO.exists():
        subprocess.run(["git", "init", "--quiet", "--bare", str(REPO)], check=True)
    # Only the live fixes' branches, so no other branch of the memory is ever read.
    refspecs = [f"+refs/heads/{PREFIX}{fix}:refs/probe/{fix}" for fix in fixes]
    fetched = subprocess.run(
        ["git", "--git-dir", str(REPO), "fetch", "--quiet", "--no-tags", REMOTE, *refspecs], capture_output=True
    )
    if fetched.returncode != 0:
        err = fetched.stderr.decode()
        # A fix that has asked nothing yet has no branch, which fetch reports as a missing ref.
        if "couldn't find remote ref" not in err:
            print(f"spike-probe: fetch failed: {err[-300:]}", file=sys.stderr)
        for fix in fixes:
            subprocess.run(
                ["git", "--git-dir", str(REPO), "fetch", "--quiet", "--no-tags", REMOTE, f"+refs/heads/{PREFIX}{fix}:refs/probe/{fix}"],
                capture_output=True,
            )
    budget = PER_POLL
    for fix in fixes:
        ref = f"refs/probe/{fix}"
        if subprocess.run(["git", "--git-dir", str(REPO), "rev-parse", "--verify", "--quiet", ref], capture_output=True).returncode:
            continue
        try:
            budget -= handle(fix, ref, budget)
            publish(fix, ref)
        except (subprocess.CalledProcessError, OSError, ValueError) as e:
            # A malformed branch only stops its own fix.
            print(f"spike-probe: skipped {fix}: {e}", file=sys.stderr)


def main() -> None:
    match sys.argv[1:]:
        case ["key", fix] if ID.match(fix):
            print(fix_key(fix).hex())
        case ["poll"]:
            poll()
        case _:
            print("usage: runner.py key <change id> | runner.py poll", file=sys.stderr)
            sys.exit(2)


if __name__ == "__main__":
    main()
