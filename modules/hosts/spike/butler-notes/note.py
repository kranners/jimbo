"""Create or append to a note under Butler/ in Aaron's Obsidian vault.

Reads one JSON line, {"op": "create" | "append", "path": "..."}, then the
note's text, from stdin, the socket butler's `note` wrapper writes to.

Each request runs a throwaway Obsidian Sync client in a private temp
directory, seeded with the read-only mirror's login: it downloads the
vault's root-level notes and Butler/ alone, every other top-level folder
excluded, writes the one note, checks that nothing else differs from the
server, then syncs once in both directions and checks the upload landed.
"""

import hashlib
import json
import os
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import unicodedata

OB = os.environ["NOTE_OB"]
CONFIG = os.environ["NOTE_CONFIG"]
MIRROR = os.environ["NOTE_MIRROR"]
FOLDER = "Butler"
DEVICE = "spike-butler"
MAX_BYTES = 100_000
MAX_DEPTH = 4
SYNC_TIMEOUT = 24
FORBIDDEN = set('\\/:*?"<>|#^[]')
TYPES = ("md", "canvas", "base")


class Refused(Exception):
    pass


def note_path(raw):
    path = unicodedata.normalize("NFC", raw.strip())
    if path.startswith(FOLDER + "/"):
        path = path[len(FOLDER) + 1:]
    if not path.endswith(".md"):
        path += ".md"
    parts = path.split("/")
    if len(parts) > MAX_DEPTH or len(path.encode()) > 200:
        raise Refused(f"path too long or deep: at most {MAX_DEPTH} levels under {FOLDER}/")
    for part in parts:
        if (
            not part
            or part.startswith((".", " "))
            or part.endswith(" ")
            or (part.endswith(".") and part != parts[-1])
            or any(c in FORBIDDEN or unicodedata.category(c)[0] == "C" for c in part)
        ):
            raise Refused(f"bad path part {part!r}: no leading dot, no edge spaces, none of \\ / : * ? \" < > | # ^ [ ]")
    if parts[-1] == ".md":
        raise Refused("the note needs a name")
    return FOLDER + "/" + path


def read_request():
    data = sys.stdin.buffer.read(MAX_BYTES + 4096)
    head, _, body = data.partition(b"\n")
    try:
        request = json.loads(head)
        op, path = request["op"], request["path"]
    except (ValueError, KeyError, TypeError):
        raise Refused("malformed request")
    if op not in ("create", "append"):
        raise Refused("op is create or append")
    if len(body) > MAX_BYTES:
        raise Refused(f"text is over {MAX_BYTES} bytes")
    try:
        text = body.decode("utf-8")
    except UnicodeDecodeError:
        raise Refused("text is not UTF-8")
    if "\0" in text:
        raise Refused("text holds a NUL byte")
    if not text.strip():
        raise Refused("the text on stdin is empty")
    return op, note_path(path), text


def source_config():
    sync = os.path.join(CONFIG, "sync")
    vaults = [
        d for d in sorted(os.listdir(sync))
        if os.path.isfile(os.path.join(sync, d, "config.json"))
    ] if os.path.isdir(sync) else []
    if len(vaults) != 1 or not os.path.isfile(os.path.join(CONFIG, "auth_token")):
        raise Refused("the notes mirror has no single Obsidian Sync vault set up; butler-notes-login has not been run")
    with open(os.path.join(sync, vaults[0], "config.json")) as f:
        return json.load(f)


def excluded_folders():
    if not os.path.isdir(MIRROR) or not os.listdir(MIRROR):
        raise Refused("the notes mirror is empty, so the vault's folders are unknown")
    return sorted(
        name for name in os.listdir(MIRROR)
        if name != FOLDER
        and not name.startswith(".")
        and "," not in name
        and name == name.strip()
        and os.path.isdir(os.path.join(MIRROR, name))
    )


def considered(path, folder, excluded):
    if path.startswith("."):
        return False
    if any(path == x or path.startswith(x + "/") for x in excluded):
        return False
    return folder or path.rsplit(".", 1)[-1].lower() in TYPES


def sha256(path):
    with open(path, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


class Client:
    def __init__(self, root, source, excluded):
        self.vault = os.path.join(root, "vault")
        self.xdg = os.path.join(root, "config")
        state = os.path.join(self.xdg, "obsidian-headless")
        self.dir = os.path.join(state, "sync", source["vaultId"])
        os.makedirs(self.dir, mode=0o700)
        os.makedirs(os.path.join(self.vault, ".obsidian"), mode=0o700)
        shutil.copyfile(os.path.join(CONFIG, "auth_token"), os.path.join(state, "auth_token"))
        self.excluded = excluded
        self.config = dict(
            source,
            vaultPath=self.vault,
            deviceName=DEVICE,
            conflictStrategy="merge",
            allowTypes=[],
            allowSpecialFiles=[],
            ignoreFolders=excluded,
        )
        self.config.pop("configDir", None)

    def sync(self, mode):
        self.config["syncMode"] = mode
        path = os.path.join(self.dir, "config.json")
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "w") as f:
            json.dump(self.config, f)
        env = dict(os.environ, XDG_CONFIG_HOME=self.xdg)
        try:
            run = subprocess.run(
                [OB, "sync", "--path", self.vault],
                env=env, stdin=subprocess.DEVNULL, capture_output=True,
                text=True, timeout=SYNC_TIMEOUT,
            )
        except subprocess.TimeoutExpired:
            raise Refused(f"Obsidian Sync did not finish within {SYNC_TIMEOUT}s ({mode}); nothing was uploaded" if mode == "pull-only" else f"Obsidian Sync did not finish uploading within {SYNC_TIMEOUT}s")
        if run.returncode != 0:
            tail = (run.stderr or run.stdout).strip().splitlines()[-3:]
            raise Refused(f"Obsidian Sync failed ({mode}, exit {run.returncode}): " + " | ".join(tail))

    def state(self):
        db = sqlite3.connect(f"file:{os.path.join(self.dir, 'state.db')}?mode=ro", uri=True)
        try:
            server = {p: json.loads(d) for p, d in db.execute("SELECT path, data FROM server_files")}
            pending = db.execute("SELECT count(*) FROM pending_files").fetchone()[0]
        finally:
            db.close()
        return {p: e for p, e in server.items() if not e.get("deleted")}, pending

    def local(self):
        found = {}
        for top, dirs, files in os.walk(self.vault):
            rel = os.path.relpath(top, self.vault)
            rel = "" if rel == "." else rel + "/"
            if not rel:
                dirs[:] = [d for d in dirs if not d.startswith(".")]
                files = [f for f in files if not f.startswith(".")]
            for d in dirs:
                found[rel + d] = True
            for f in files:
                found[rel + f] = False
        return {p: folder for p, folder in found.items() if considered(p, folder, self.excluded)}

    def check_matches_server(self, allowed):
        """Refuse unless the local copy is the server's, but for `allowed`."""
        server, pending = self.state()
        if pending:
            raise Refused(f"{pending} server changes still pending; nothing was uploaded")
        local = self.local()
        for path, entry in server.items():
            folder = bool(entry.get("folder"))
            if path in allowed or not considered(path, folder, self.excluded):
                continue
            if local.get(path) != folder:
                raise Refused(f"the local copy is missing {path!r}; nothing was uploaded")
        for path, folder in local.items():
            if path in allowed:
                continue
            entry = server.get(path)
            if entry is None or bool(entry.get("folder")) != folder:
                raise Refused(f"the local copy has {path!r}, which the server lacks; nothing was uploaded")
            if not folder and entry.get("hash") != sha256(os.path.join(self.vault, path)):
                raise Refused(f"the local copy of {path!r} differs from the server's; nothing was uploaded")


def write(client, op, path, text):
    target = os.path.join(client.vault, path)
    if os.path.lexists(target) and not os.path.isfile(target):
        raise Refused(f"{path} is not a note")
    exists = os.path.isfile(target)
    if op == "create" and exists:
        raise Refused(f"{path} already exists; append to it, or pick another name")
    if op == "append" and not exists:
        raise Refused(f"{path} does not exist; create it first")
    new = []
    parent = os.path.dirname(target)
    while not os.path.isdir(parent):
        new.append(os.path.relpath(parent, client.vault))
        parent = os.path.dirname(parent)
    os.makedirs(os.path.dirname(target), mode=0o700, exist_ok=True)
    if not text.endswith("\n"):
        text += "\n"
    if op == "append":
        with open(target, "rb") as f:
            old = f.read()
        if old and not old.endswith(b"\n"):
            text = "\n" + text
        with open(target, "a", encoding="utf-8") as f:
            f.write(text)
    else:
        with open(target, "x", encoding="utf-8") as f:
            f.write(text)
    return {path, *new}


def main():
    try:
        op, path, text = read_request()
        source = source_config()
        with tempfile.TemporaryDirectory(prefix="butler-note-") as root:
            client = Client(root, source, excluded_folders())
            client.sync("pull-only")
            client.check_matches_server(set())
            allowed = write(client, op, path, text)
            client.check_matches_server(allowed)
            client.sync("bidirectional")
            server, _ = client.state()
            entry = server.get(path)
            if not entry or entry.get("hash") != sha256(os.path.join(client.vault, path)):
                raise Refused(f"{path} did not reach Obsidian Sync; try again")
    except Refused as e:
        print(f"note: {e}")
        return 1
    done = "created" if op == "create" else "appended to"
    print(f"{done} {path}; it is on Obsidian Sync now and reaches Aaron's devices as they sync")
    return 0


if __name__ == "__main__":
    sys.exit(main())
