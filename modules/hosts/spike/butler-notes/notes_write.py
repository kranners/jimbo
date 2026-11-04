"""butler-notes-write: apply butler's `note` requests to Aaron's Obsidian vault and push them to Obsidian Sync.

Run as butler outside the daemon's sandbox, whenever ~/.cache/notes-write/spool holds a request.
butler-notes-sync keeps the vault a download-only mirror, so each request first pulls, then
writes the one note, commits it before and after to the vault's own git history in
history.git, pushes it with a bidirectional sync, and pulls again in mirror mode, which
reverts anything the push did not deliver, so the note still matching proves it landed.
Nothing here deletes a note.
"""

import fcntl
import hashlib
import json
import os
import re
import subprocess
import sys
import time
from datetime import datetime, timezone

NOTES = os.environ.get("NOTES_DIR", "/var/lib/butler-notes")
VAULT = os.path.join(NOTES, "vault")
HISTORY = os.path.join(NOTES, "history.git")
LOG = os.path.join(NOTES, "writes.jsonl")
LOCK = os.path.join(NOTES, "write.lock")
SPOOL = os.environ.get("NOTES_WRITE_DIR", "/var/lib/butler/.cache/notes-write")
OB = os.environ.get("OB", "ob")
# For tests: skip Obsidian Sync and touch only the local vault and its history.
OFFLINE = os.environ.get("NOTES_OFFLINE") == "1"
MAX_NOTE = 400_000
MAX_SHOWN = 60_000
BAD_CHARS = re.compile(r'[\\:*?"<>|#^\[\]\x00-\x1f]')
EX_USAGE = 64
EX_DATAERR = 65
EX_NOINPUT = 66
EX_CANTCREAT = 73
EX_TEMPFAIL = 75


class Refused(Exception):
    def __init__(self, message, code=EX_DATAERR):
        super().__init__(message)
        self.code = code


def digest(data):
    return hashlib.sha256(data).hexdigest()


def note_path(raw):
    raw = (raw or "").strip().replace("\\", "/").strip("/")
    if not raw.lower().endswith(".md"):
        raw += ".md"
    parts = raw.split("/")
    if len(raw) > 400 or any(not part or part in (".", "..") or part.startswith(".") or part != part.strip() for part in parts):
        raise Refused(f"not a note path in the vault: {raw}", EX_USAGE)
    if any(BAD_CHARS.search(part) for part in parts):
        raise Refused('a note name may not hold \\ : * ? " < > | # ^ [ ] or control characters', EX_USAGE)
    full = VAULT
    for part in parts:
        full = os.path.join(full, part)
        if os.path.islink(full):
            raise Refused(f"{raw} goes through a link, which notes never follow", EX_USAGE)
    return raw, full


def git(*args, check=True):
    env = dict(os.environ, GIT_DIR=HISTORY, GIT_WORK_TREE=VAULT)
    command = ["git", "-c", "user.name=Butler", "-c", "user.email=butler@spike", "-c", "core.quotepath=off", *args]
    done = subprocess.run(command, env=env, capture_output=True, text=True)
    if check and done.returncode != 0:
        raise Refused(f"the vault's history failed: {done.stderr.strip() or done.stdout.strip()}", EX_TEMPFAIL)
    return done.stdout


def snapshot(rel, message):
    """Commit the note as it is on disk, if it differs from its last saved version, and return the commit."""
    if not os.path.isdir(HISTORY):
        subprocess.run(["git", "init", "--quiet", "--bare", HISTORY], check=True)
        git("config", "core.bare", "false")
    git("add", "--", rel)
    if git("diff", "--cached", "--name-only", "--", rel).strip():
        git("commit", "--quiet", "-m", message, "--", rel)
    return git("rev-parse", "--short", "HEAD", check=False).strip() or None


def ob(*args):
    for _ in range(30):
        done = subprocess.run([OB, *args, "--path", VAULT], capture_output=True, text=True, timeout=600)
        if done.returncode == 0:
            return
        said = (done.stderr + done.stdout).strip()
        if "already running" not in said:
            raise Refused(f"Obsidian Sync failed: {said[-400:] or 'exit %d' % done.returncode}", EX_TEMPFAIL)
        time.sleep(2)
    raise Refused("Obsidian Sync stayed busy with another sync; try again in a few minutes", EX_TEMPFAIL)


def wait_for_mirror():
    # The 15-minute mirror flips the vault back to mirror-remote as it starts, which would revert a pending edit.
    for _ in range(120):
        state = subprocess.run(["systemctl", "is-active", "butler-notes-sync.service"], capture_output=True, text=True).stdout.strip()
        if state not in ("active", "activating", "deactivating"):
            return
        time.sleep(2)


def pull():
    if OFFLINE:
        return
    wait_for_mirror()
    ob("sync")


def push():
    if OFFLINE:
        return
    wait_for_mirror()
    try:
        ob("sync-config", "--mode", "bidirectional")
        ob("sync")
    finally:
        ob("sync-config", "--mode", "mirror-remote")
    ob("sync")


def read_bytes(full):
    try:
        with open(full, "rb") as handle:
            return handle.read()
    except FileNotFoundError:
        return None


def write_bytes(full, data):
    os.makedirs(os.path.dirname(full), exist_ok=True)
    partial = os.path.join(os.path.dirname(full), f".butler-{os.getpid()}.partial")
    with open(partial, "wb") as out:
        out.write(data)
    os.replace(partial, full)


def log(entry):
    entry["at"] = datetime.now(timezone.utc).isoformat(timespec="seconds")
    with open(LOG, "a", encoding="utf-8") as out:
        out.write(json.dumps(entry) + "\n")
    print(json.dumps(entry), flush=True)


def handle(request):
    verb, arg = request.get("verb"), request.get("arg")
    rel, full = note_path(request.get("path"))
    pull()
    current = read_bytes(full)
    if current is not None and len(current) > MAX_NOTE:
        raise Refused(f"{rel} is over {MAX_NOTE // 1000} kB, too big to work on")

    if verb == "read":
        if current is None:
            raise Refused(f"no note {rel}", EX_NOINPUT)
        text = current.decode("utf-8", "replace")
        shown = text if len(text) <= MAX_SHOWN else text[:MAX_SHOWN] + f"\n[cut off after {MAX_SHOWN} characters]"
        return f"{rel}\nsha256 {digest(current)}\n---\n{shown}"
    if verb == "history":
        if not os.path.isdir(HISTORY):
            return f"no saved versions of {rel} yet"
        lines = git("log", "--max-count=30", "--format=%h %ad %s", "--date=format-local:%a %d %b %Y %H:%M", "--", rel, check=False).strip()
        return lines or f"no saved versions of {rel} yet"

    text = (request.get("text") or "").encode()
    if verb == "create":
        if current is not None:
            raise Refused(f"{rel} already exists; append to it or replace it", EX_CANTCREAT)
        new = text if text.endswith(b"\n") else text + b"\n"
    elif verb == "append":
        if current is None:
            raise Refused(f"no note {rel} to append to; create it", EX_NOINPUT)
        joiner = b"" if not current or current.endswith(b"\n\n") else (b"\n" if current.endswith(b"\n") else b"\n\n")
        new = current + joiner + (text if text.endswith(b"\n") else text + b"\n")
    elif verb == "replace":
        if current is None:
            raise Refused(f"no note {rel} to replace; create it", EX_NOINPUT)
        if digest(current) != arg:
            raise Refused(f"{rel} has changed since you read it; read it again with `note read` and redo the edit on that")
        new = text
    elif verb == "restore":
        if not os.path.isdir(HISTORY):
            raise Refused(f"no saved versions of {rel}", EX_NOINPUT)
        shown = subprocess.run(["git", "show", f"{arg}:{rel}"], env=dict(os.environ, GIT_DIR=HISTORY), capture_output=True)
        if shown.returncode != 0:
            raise Refused(f"commit {arg} holds no version of {rel}; see `note history`", EX_NOINPUT)
        new = shown.stdout
    else:
        raise Refused(f"unknown request {verb}", EX_USAGE)
    if len(new) > MAX_NOTE:
        raise Refused(f"the note would be over {MAX_NOTE // 1000} kB")
    if new == current:
        return f"{rel} already says that; nothing changed"

    before = snapshot(rel, f"Before butler's {verb}: {rel}") if current is not None else None
    write_bytes(full, new)
    after = snapshot(rel, f"Butler {verb}{' ' + arg if verb == 'restore' else ''}: {rel}")
    try:
        push()
    except Refused as error:
        log({"verb": verb, "path": rel, "ok": False, "before": before, "after": after, "error": str(error)})
        raise
    landed = read_bytes(full)
    if landed != new:
        log({"verb": verb, "path": rel, "ok": False, "before": before, "after": after, "error": "did not stick"})
        raise Refused(f"the {verb} of {rel} did not reach Obsidian Sync, or Aaron changed the note at the same moment; read it again, and `note restore {rel} {after}` puts butler's version back", EX_TEMPFAIL)
    log({"verb": verb, "path": rel, "ok": True, "bytes": len(new), "sha256": digest(new), "before": before, "after": after})
    undo = f"; `note restore {rel} {before}` undoes it" if before else ""
    done = {"create": "created", "append": "appended to", "replace": "replaced", "restore": "restored"}[verb]
    return f"{done} {rel} ({len(new)} bytes), synced to Obsidian Sync as version {after}{undo}"


def main():
    spool, results = os.path.join(SPOOL, "spool"), os.path.join(SPOOL, "results")
    os.makedirs(results, mode=0o700, exist_ok=True)
    now = time.time()
    for old in os.listdir(results):
        if now - os.path.getmtime(os.path.join(results, old)) > 86400:
            os.unlink(os.path.join(results, old))
    with open(LOCK, "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        # Requests arrive seconds apart in a burst, so keep going until the spool stays empty.
        while True:
            time.sleep(0.5)
            pending = sorted((entry for entry in os.listdir(spool) if entry.endswith(".json")), key=lambda entry: os.path.getmtime(os.path.join(spool, entry)))
            if not pending:
                return
            for entry in pending:
                source = os.path.join(spool, entry)
                try:
                    with open(source, encoding="utf-8") as handle:
                        request = json.load(handle)
                    result = {"ok": True, "output": handle_safely(request)}
                except Refused as error:
                    result = {"ok": False, "error": str(error), "code": error.code}
                except (ValueError, OSError, subprocess.SubprocessError) as error:
                    result = {"ok": False, "error": f"failed: {error}", "code": EX_TEMPFAIL}
                os.unlink(source)
                partial = os.path.join(results, f".{entry}.partial")
                with open(partial, "w", encoding="utf-8") as out:
                    json.dump(result, out)
                os.rename(partial, os.path.join(results, entry))


def handle_safely(request):
    if not isinstance(request, dict):
        raise Refused("not a request", EX_USAGE)
    return handle(request)


if __name__ == "__main__":
    sys.exit(main())
