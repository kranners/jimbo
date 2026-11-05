"""asset: butler's shared store of the pictures, logos, decks and exports it makes for Aaron.

Every thread, call, scheduled run and change sees the same store, so what one made another can find and reuse.
The store lives in butler's home on spike alone, never in a repository, and work-tagged assets never leave it but
for Aaron himself.
"""

import contextlib
import fcntl
import hashlib
import json
import os
import re
import shutil
import sys
import time
from datetime import datetime, timezone

STORE = "@store@"
OUTBOX = "@outbox@"
# Where an asset may be copied from: what butler made, what Aaron attached, what mac fetched into the outbox, and the
# store itself, so a source can never be a credential or state file the daemon's Read is denied.
SOURCES = [p for p in "@sources@".split(":") if p]
FILES = os.path.join(STORE, "files")
TRASH = os.path.join(STORE, "trash")
MANIFEST = os.path.join(STORE, "manifest.json")
LOCK = os.path.join(STORE, ".lock")
MAX_BYTES = 200 << 20
NAME = re.compile(r"^[a-z0-9][a-z0-9-]{0,63}$")
TAG = re.compile(r"^[a-z0-9][a-z0-9-]{0,31}$")
KINDS = {
    "image": {".png", ".jpg", ".jpeg", ".webp", ".gif", ".svg", ".heic", ".bmp", ".tif", ".tiff", ".ico"},
    "video": {".mp4", ".mov", ".webm", ".mkv"},
    "audio": {".wav", ".mp3", ".m4a", ".ogg", ".flac", ".opus"},
    "deck": {".pptx", ".ppt", ".key", ".odp"},
    "spreadsheet": {".xlsx", ".xls", ".csv", ".tsv", ".ods", ".numbers"},
    "document": {".pdf", ".docx", ".doc", ".md", ".txt", ".html", ".rtf", ".odt", ".pages", ".json"},
    "archive": {".zip", ".tar", ".gz", ".tgz", ".7z"},
}
USAGE = """usage:
  asset add <path> <name> [description...] [--tags a,b] [--task words] [--kind kind]
  asset list [search words...] [--tag tag]
  asset show <name>
  asset remove <name>
A name is lowercase letters, digits and hyphens, such as trip-itinerary-may-2027. Adding a file already in the store
renames, describes or tags that asset instead of storing it twice."""


def fail(message, code=1):
    print(f"asset: {message}", file=sys.stderr)
    sys.exit(code)


def now():
    return datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds")


@contextlib.contextmanager
def locked():
    os.makedirs(FILES, mode=0o700, exist_ok=True)
    with open(LOCK, "a") as handle:
        fcntl.flock(handle, fcntl.LOCK_EX)
        yield


def load():
    try:
        with open(MANIFEST) as handle:
            return json.load(handle)
    except FileNotFoundError:
        return {"assets": []}


def save(manifest):
    manifest["assets"].sort(key=lambda a: a["created"], reverse=True)
    partial = MANIFEST + ".partial"
    with open(partial, "w") as handle:
        json.dump(manifest, handle, indent=2, ensure_ascii=False)
        handle.write("\n")
    os.replace(partial, MANIFEST)


def kind_of(path):
    ext = os.path.splitext(path)[1].lower()
    return next((kind for kind, exts in KINDS.items() if ext in exts), "other")


def sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def check_source(path):
    if not os.path.isfile(path) or os.path.islink(path):
        fail(f"{path} is not a regular file", 2)
    real = os.path.realpath(path)
    if not any(real.startswith(root.rstrip("/") + "/") for root in SOURCES):
        fail("an asset is copied from the outbox, Aaron's Discord attachments or the store itself; "
             "fetch a file from a Mac into the outbox first with `mac <host> fetch <file> outbox`", 2)
    if os.path.getsize(real) > MAX_BYTES:
        fail(f"{path} is over {MAX_BYTES >> 20} MB", 2)
    return real


def parse_tags(text):
    tags = [t.strip().lower() for t in text.split(",") if t.strip()]
    for tag in tags:
        if not TAG.match(tag):
            fail(f"a tag is lowercase letters, digits and hyphens, not {tag!r}", 2)
    return tags


def split_flags(args, known):
    words, flags = [], {}
    it = iter(args)
    for arg in it:
        if arg in known:
            value = next(it, None)
            if value is None:
                fail(f"{arg} needs a value", 2)
            flags[arg] = value
        elif arg.startswith("--"):
            fail(f"unknown option {arg}\n{USAGE}", 2)
        else:
            words.append(arg)
    return words, flags


def slug(text):
    return re.sub(r"-+", "-", re.sub(r"[^a-z0-9]+", "-", text.lower())).strip("-")[:64] or "asset"


def free_name(assets, name, skip=None):
    taken = {a["name"] for a in assets if a is not skip}
    candidate, n = name, 2
    while candidate in taken:
        candidate = f"{name[:60]}-{n}"
        n += 1
    return candidate


def stored_path(entry):
    return os.path.join(STORE, entry["file"])


def store_file(source, name, ext):
    target = os.path.join(FILES, name + ext)
    partial = target + ".partial"
    shutil.copyfile(source, partial)
    os.chmod(partial, 0o600)
    os.replace(partial, target)
    return os.path.relpath(target, STORE)


def add(args, auto=False):
    words, flags = split_flags(args, {"--tags", "--task", "--kind"})
    if len(words) < (1 if auto else 2):
        fail(USAGE, 2)
    source = check_source(words[0])
    ext = os.path.splitext(source)[1].lower()[:10]
    if auto:
        name, description = slug(os.path.splitext(os.path.basename(source))[0]), " ".join(words[1:])
    else:
        name, description = words[1], " ".join(words[2:])
        if not NAME.match(name):
            fail(f"a name is lowercase letters, digits and hyphens, at most 64, such as {slug(name)}", 2)
    tags = parse_tags(flags.get("--tags", ""))
    if auto:
        tags = sorted(set(tags) | {"auto"})
    kind = flags.get("--kind") or kind_of(source)
    digest = sha256(source)
    with locked():
        manifest = load()
        assets = manifest["assets"]
        same = next((a for a in assets if a["sha256"] == digest), None)
        if same is not None:
            if auto:
                print(f"already stored as {same['name']}")
                return
            clash = next((a for a in assets if a["name"] == name and a is not same), None)
            if clash is not None:
                fail(f"the name {name} is taken by another asset; pick another", 2)
            if same["name"] != name:
                old = stored_path(same)
                new = os.path.join(FILES, name + os.path.splitext(old)[1])
                os.replace(old, new)
                same["file"] = os.path.relpath(new, STORE)
                same["name"] = name
            if description:
                same["description"] = description
            if "--tags" in flags:
                same["tags"] = sorted(set(t for t in same.get("tags", []) if t != "auto") | set(tags))
            else:
                same["tags"] = [t for t in same.get("tags", []) if t != "auto"]
            if "--task" in flags:
                same["task"] = flags["--task"]
            if "--kind" in flags:
                same["kind"] = kind
            same["updated"] = now()
            save(manifest)
            print(f"updated {name}, already stored")
            print(describe(same))
            return
        if auto:
            name = free_name(assets, name)
        elif any(a["name"] == name for a in assets):
            fail(f"the name {name} is taken by another asset; pick another, or `asset show {name}` to reuse it", 2)
        entry = {
            "name": name,
            "kind": kind,
            "description": description,
            "tags": sorted(set(tags)),
            "task": flags.get("--task", ""),
            "created": now(),
            "source": source,
            "file": store_file(source, name, ext),
            "sha256": digest,
            "bytes": os.path.getsize(source),
        }
        assets.append(entry)
        save(manifest)
    if auto:
        print(f"saved as asset {name}")
    else:
        print(f"saved {name}")
        print(describe(entry))


def describe(a):
    lines = [
        f"{a['name']} ({a['kind']}, {a['bytes'] // 1024} KB, {a['created'][:16].replace('T', ' ')})",
    ]
    if a.get("description"):
        lines.append(f"  {a['description']}")
    if a.get("tags"):
        lines.append(f"  tags: {', '.join(a['tags'])}")
    if a.get("task"):
        lines.append(f"  task: {a['task']}")
    return "\n".join(lines)


def find(assets, name):
    entry = next((a for a in assets if a["name"] == name), None)
    if entry is None:
        close = [a["name"] for a in assets if name in a["name"]][:5]
        fail(f"no asset named {name}" + (f"; did you mean {', '.join(close)}" if close else "; try `asset list`"), 1)
    return entry


def list_assets(args):
    words, flags = split_flags(args, {"--tag"})
    tag = flags.get("--tag", "").lower()
    terms = [w.lower() for w in words]
    shown = 0
    for a in load()["assets"]:
        text = " ".join([a["name"], a["kind"], a.get("description", ""), a.get("task", ""), " ".join(a.get("tags", []))]).lower()
        if tag and tag not in a.get("tags", []):
            continue
        if all(t in text for t in terms):
            print(describe(a))
            shown += 1
            if shown == 50:
                print("(the first 50; narrow the search)")
                break
    if not shown:
        print("no assets match" if terms or tag else "the store is empty")


def show(args):
    if len(args) != 1:
        fail(USAGE, 2)
    a = find(load()["assets"], args[0])
    path = stored_path(a)
    print(describe(a))
    print(f"  stored: {path}")
    print(f"  from: {a.get('source', '')}")
    if "work" in a.get("tags", []):
        print("  work: keep it in Aaron's private places; never in a public repository or anywhere public")
    if a["kind"] == "image" or a["kind"] in ("video", "audio", "deck", "document", "spreadsheet"):
        os.makedirs(OUTBOX, exist_ok=True)
        out = os.path.join(OUTBOX, "asset-" + os.path.basename(path))
        shutil.copyfile(path, out)
        os.utime(out)
        print(f"attach: {out}")


def remove(args):
    if len(args) != 1:
        fail(USAGE, 2)
    with locked():
        manifest = load()
        a = find(manifest["assets"], args[0])
        os.makedirs(TRASH, mode=0o700, exist_ok=True)
        stamp = time.strftime("%Y%m%dT%H%M%S")
        os.replace(stored_path(a), os.path.join(TRASH, f"{stamp}-{os.path.basename(a['file'])}"))
        manifest["assets"].remove(a)
        a["removed"] = now()
        with open(os.path.join(TRASH, "removed.jsonl"), "a") as handle:
            handle.write(json.dumps(a, ensure_ascii=False) + "\n")
        save(manifest)
    print(f"removed {a['name']}; its file is kept in {TRASH}, so Aaron can still get it back")


def main():
    args = sys.argv[1:]
    if not args:
        fail(USAGE, 2)
    verb, rest = args[0], args[1:]
    if verb == "add":
        add(rest)
    elif verb == "auto":
        add(rest, auto=True)
    elif verb == "list":
        list_assets(rest)
    elif verb == "show":
        show(rest)
    elif verb == "remove":
        remove(rest)
    else:
        fail(USAGE, 2)


if __name__ == "__main__":
    main()
