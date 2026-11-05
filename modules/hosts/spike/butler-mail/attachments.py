# mail's attachments and save actions: lists one message's attachments, or saves one of them into butler's index
# inbox through the drop spool `mac fetch` uses, read-only on the mailbox, since himalaya's --raw read leaves every flag
# alone and nothing here moves, archives or deletes mail. Saved files never go to the outbox.
import email
import email.policy
import json
import os
import re
import subprocess
import sys
import time

HIMALAYA = "@himalaya@"
CONFIG = "@config@"
DROP = "@drop@"
LOG = "@log@"
DROP_MAX = int("@dropMax@")
FOLDER = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")
DROP_NAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._ ()+,-]{0,199}$")


def fail(message, code=1):
    print(f"mail: {message}", file=sys.stderr)
    sys.exit(code)


def raw_message(account, mailbox, identifier):
    command = [HIMALAYA, "--config", CONFIG, "--log-level", "off", "--account", account, "message", "read", "--raw"]
    if mailbox:
        command += ["--mailbox", mailbox]
    result = subprocess.run(command + [identifier], capture_output=True, timeout=300)
    if result.returncode != 0:
        detail = (result.stderr or result.stdout).decode(errors="replace").strip()[:300]
        hint = "" if mailbox else f"; an id belongs to its folder, so name the folder as in: mail {account} <folder> attachments {identifier}"
        fail(f"could not read message {identifier} in {account}: {detail or 'himalaya exited %d' % result.returncode}{hint}")
    return email.message_from_bytes(result.stdout, policy=email.policy.default)


def attachments(message):
    found = []
    for part in message.walk():
        if part.is_multipart():
            continue
        name = part.get_filename()
        if name or part.get_content_disposition() == "attachment":
            data = part.get_payload(decode=True) or b""
            found.append((name or f"attachment-{len(found) + 1}", part.get_content_type(), data))
    return found


def drop_name(name):
    base = name.replace("\\", "/").rsplit("/", 1)[-1]
    if DROP_NAME.match(base) and not base.endswith(".partial"):
        return base
    return re.sub(r"[^A-Za-z0-9._ ()+,-]", "_", base).lstrip("._ -")[:200] or "attachment"


def log(entry):
    entry["at"] = time.strftime("%Y-%m-%dT%H:%M:%S%z")
    os.makedirs(os.path.dirname(LOG), mode=0o700, exist_ok=True)
    with open(LOG, "a") as handle:
        handle.write(json.dumps(entry) + "\n")
    print(f"mail save: {json.dumps(entry)}", file=sys.stderr)


def save(account, mailbox, identifier, wanted, folder, message):
    if not FOLDER.match(folder) or folder in ("browser", "outbox"):
        fail(f"the inbox folder is one lowercase name of the index inbox, such as exports or didi, not {folder}", 2)
    found = attachments(message)
    matches = [item for item in found if item[0] == wanted] or [item for item in found if item[0].lower() == wanted.lower()]
    if not matches:
        fail(f"message {identifier} has no attachment named {wanted!r}; it has: {', '.join(item[0] for item in found) or 'none'}", 2)
    name, kind, data = matches[0]
    if len(data) > DROP_MAX:
        fail(f"{name} is {len(data) >> 20} MB, over the {DROP_MAX >> 20} MB limit")
    target = drop_name(name)
    partials, spool, results = (os.path.join(DROP, part) for part in ("partial", "spool", "results"))
    for path in (partials, spool, results):
        os.makedirs(path, mode=0o700, exist_ok=True)
    entry = f"{folder}--{target}"
    answer = os.path.join(results, entry)
    try:
        os.unlink(answer)
    except FileNotFoundError:
        pass
    partial = os.path.join(partials, f"{os.getpid()}-mail-{target}")
    with open(partial, "wb") as handle:
        handle.write(data)
    os.rename(partial, os.path.join(spool, entry))
    record = {"account": account, "folder": mailbox or "inbox", "id": identifier, "subject": str(message.get("subject", ""))[:200],
              "attachment": name, "bytes": len(data), "type": kind, "inbox": f"{folder}/{target}"}
    deadline = time.time() + 30
    while time.time() < deadline and not os.path.exists(answer):
        time.sleep(0.5)
    if not os.path.exists(answer):
        record["result"] = "spooled"
        log(record)
        print(f"saved {name} ({len(data)} bytes) to spike's drop spool for the index inbox {folder}/{target}; it has not answered yet, so check again later")
        return
    with open(answer) as handle:
        verdict = handle.read().strip()
    os.unlink(answer)
    record["result"] = verdict
    log(record)
    if not verdict.startswith("ok"):
        fail(f"the index inbox refused {target}: {verdict.partition(' ')[2] or verdict}")
    print(f"saved {name} ({len(data)} bytes) from {account} message {identifier} into the index inbox as {folder}/{target}; the ingest picks it up from there")


def main():
    action, account, mailbox, identifier, *rest = sys.argv[1:]
    message = raw_message(account, mailbox, identifier)
    if action == "attachments":
        found = attachments(message)
        if not found:
            print(f"Message {identifier} has no attachments.")
            return
        print("NAME\tTYPE\tBYTES")
        for name, kind, data in found:
            print(f"{name}\t{kind}\t{len(data)}")
        print(f"Save one into the index inbox with: mail {account} {mailbox + ' ' if mailbox else ''}save {identifier} <name> [inbox folder]")
    else:
        save(account, mailbox, identifier, rest[0], rest[1] if len(rest) > 1 else "exports", message)


if __name__ == "__main__":
    main()
