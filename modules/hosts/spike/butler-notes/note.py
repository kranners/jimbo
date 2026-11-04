"""butler's `note`: read and write Aaron's Obsidian vault, Latte, through butler-notes-write.

The daemon's sandbox sees the vault read-only and never the Obsidian Sync login, so every
request is spooled as JSON under ~/.cache/notes-write, which butler's Read is denied, and
butler-notes-write, run outside the sandbox, pulls the vault, applies it, commits it to the
vault's git history, pushes it to Obsidian Sync and answers in the results folder.
"""

import json
import os
import re
import sys
import time
import uuid

SPOOL = os.environ.get("NOTES_WRITE_DIR", os.path.expanduser("~/.cache/notes-write"))
WAIT_SECONDS = 150
MAX_TEXT = 200_000
EX_USAGE = 64
EX_TEMPFAIL = 75
SHA = re.compile(r"^[0-9a-f]{64}$")
COMMIT = re.compile(r"^[0-9a-f]{7,40}$")

USAGE = """usage:
  note read <path>                     (the note as Obsidian Sync has it now, with its sha256)
  note create <path>                   (stdin: a new note; refuses if one is there)
  note append <path>                   (stdin: text added to the end of an existing note)
  note replace <path> <sha256>         (stdin: the whole new note; refuses unless the note still has that sha256)
  note history <path>                  (the note's saved versions, newest first)
  note restore <path> <commit>         (puts a saved version back, as a new edit)
<path> is relative to the vault, such as "Travel/Tokyo trip"; .md is optional."""

VERBS = {
    "read": (1, False),
    "create": (1, True),
    "append": (1, True),
    "replace": (2, True),
    "history": (1, False),
    "restore": (2, False),
}


def fail(message, code):
    print(f"note: {message}", file=sys.stderr)
    sys.exit(code)


def main():
    args = sys.argv[1:]
    if not args or args[0] not in VERBS or len(args) - 1 != VERBS[args[0]][0]:
        fail(USAGE, EX_USAGE)
    verb, path = args[0], args[1]
    extra = args[2] if len(args) > 2 else None
    if verb == "replace" and not SHA.match(extra):
        fail("replace takes the sha256 `note read` printed for the version you edited", EX_USAGE)
    if verb == "restore" and not COMMIT.match(extra):
        fail("restore takes a commit from `note history`", EX_USAGE)
    text = None
    if VERBS[verb][1]:
        text = sys.stdin.read()
        if not text.strip():
            fail(f"{verb} needs the text on stdin", EX_USAGE)
        if len(text.encode()) > MAX_TEXT:
            fail(f"the text is over {MAX_TEXT // 1000} kB", EX_USAGE)

    ident = uuid.uuid4().hex
    spool, results = os.path.join(SPOOL, "spool"), os.path.join(SPOOL, "results")
    for folder in (spool, results):
        os.makedirs(folder, mode=0o700, exist_ok=True)
    partial = os.path.join(SPOOL, f".{ident}.partial")
    with open(partial, "w", encoding="utf-8") as out:
        json.dump({"id": ident, "verb": verb, "path": path, "arg": extra, "text": text}, out)
    os.rename(partial, os.path.join(spool, f"{ident}.json"))

    answer = os.path.join(results, f"{ident}.json")
    deadline = time.time() + WAIT_SECONDS
    while time.time() < deadline and not os.path.exists(answer):
        time.sleep(0.5)
    if not os.path.exists(answer):
        fail(f"the vault has not answered in {WAIT_SECONDS} s; the request {ident[:8]} is still queued and may yet land, so check with `note read` before trying again", EX_TEMPFAIL)
    with open(answer, encoding="utf-8") as handle:
        result = json.load(handle)
    os.unlink(answer)
    if result.get("ok"):
        print(result.get("output", ""))
        return
    fail(result.get("error", "failed"), result.get("code", 1))


main()
