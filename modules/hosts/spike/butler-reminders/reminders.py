import fcntl
import json
import os
import re
import subprocess
import sys
from datetime import date, datetime, time, timedelta, timezone

os.environ.setdefault("PYTHON_KEYRING_BACKEND", "keyring.backends.null.Keyring")

import requests
from pyicloud import PyiCloudService
from pyicloud.exceptions import (
    PyiCloudAPIResponseException,
    PyiCloud2FARequiredException,
    PyiCloud2SARequiredException,
    PyiCloudAuthRequiredException,
    PyiCloudFailedLoginException,
    PyiCloudNoStoredPasswordAvailableException,
    PyiCloudServiceUnavailable,
)
from pyicloud.services.reminders.client import RemindersApiError, RemindersAuthError
from tzlocal import get_localzone

COOKIE_DIRECTORY = "/var/lib/butler/.local/share/pyicloud"
APPLE_ID_FILE = os.path.join(COOKIE_DIRECTORY, "apple-id")
EX_TEMPFAIL = 75
# Every reminder added, from a conversation or a scheduled run, goes to audit/reminders in butler's memory.
MEMORY_AUDIT = "@memoryAudit@"
AUDIT_SPOOL = os.path.expanduser("~/.local/state/reminders/audit-spool")
LOCAL = get_localzone()

USAGE = """usage: reminders lists
       reminders due [days]
       reminders open [list title]
       reminders add <list title> <title> [YYYY-MM-DD[THH:MM]]
       reminders complete <id>
       reminders update <id> [--title T] [--due YYYY-MM-DD[THH:MM]|none] [--notes N] [--flagged yes|no]
       reminders delete <id>"""

EXPIRED = (
    PyiCloud2FARequiredException,
    PyiCloud2SARequiredException,
    PyiCloudAuthRequiredException,
    PyiCloudFailedLoginException,
    PyiCloudNoStoredPasswordAvailableException,
)


def usage():
    print(USAGE, file=sys.stderr)
    sys.exit(2)


def expired():
    print(
        "iCloud session expired: ask Aaron to run `sudo -u butler butler-icloud-login <apple-id>`",
        file=sys.stderr,
    )
    sys.exit(EX_TEMPFAIL)


def connect():
    try:
        with open(APPLE_ID_FILE) as file:
            apple_id = file.read().strip()
    except FileNotFoundError:
        expired()
    try:
        api = PyiCloudService(apple_id, cookie_directory=COOKIE_DIRECTORY)
        if api.requires_2fa or api.requires_2sa:
            expired()
        return api.reminders
    except EXPIRED:
        expired()
    except PyiCloudServiceUnavailable as error:
        print(f"iCloud Reminders is unavailable: {error}", file=sys.stderr)
        sys.exit(1)


def due_of(reminder):
    if reminder.due_date is None:
        return None
    due = reminder.due_date
    if due.tzinfo is None:
        due = due.replace(tzinfo=timezone.utc)
    if reminder.all_day:
        return due.astimezone(timezone.utc).date()
    return due.astimezone(LOCAL)


def moment(due):
    if isinstance(due, datetime):
        return due
    return datetime.combine(due, time.min, LOCAL)


def overdue(due):
    if isinstance(due, datetime):
        return due < datetime.now(LOCAL)
    return due < date.today()


def describe(reminder, list_titles):
    due = due_of(reminder)
    entry = {
        "id": reminder.id,
        "list": list_titles.get(reminder.list_id, reminder.list_id),
        "title": reminder.title,
        "due": due.isoformat() if due else None,
        "overdue": bool(due) and not reminder.completed and overdue(due),
        "flagged": reminder.flagged,
        "completed": reminder.completed,
    }
    if reminder.desc:
        entry["notes"] = reminder.desc
    return entry


def print_json(value):
    json.dump(value, sys.stdout, ensure_ascii=False, indent=1)
    print()


def usable_lists(service):
    return [lst for lst in service.lists() if not lst.deleted and not lst.is_group]


def find_list(lists, title):
    for lst in lists:
        if lst.title.casefold() == title.casefold():
            return lst
    titles = ", ".join(lst.title for lst in lists)
    print(f"no list called {title!r}; the lists are {titles}", file=sys.stderr)
    sys.exit(1)


def open_reminders(service, lists):
    for lst in lists:
        result = service.list_reminders(lst.id, include_completed=False)
        for reminder in result.reminders:
            if not reminder.completed and not reminder.deleted:
                yield reminder


def by_due(reminder):
    due = due_of(reminder)
    if due is None:
        return (1, datetime.max.replace(tzinfo=timezone.utc), reminder.title)
    return (0, moment(due), reminder.title)


def parse_due(text):
    if re.fullmatch(r"\d{4}-\d{2}-\d{2}", text):
        day = date.fromisoformat(text)
        return datetime(day.year, day.month, day.day, tzinfo=timezone.utc), True
    if re.fullmatch(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}", text):
        return datetime.fromisoformat(text).replace(tzinfo=LOCAL), False
    usage()


def lists_command(service, args):
    if args:
        usage()
    print_json([{"title": lst.title, "count": lst.count} for lst in usable_lists(service)])


def due_command(service, args):
    if len(args) > 1 or (args and not re.fullmatch(r"[1-9]\d{0,2}", args[0])):
        usage()
    days = int(args[0]) if args else 1
    cutoff = datetime.combine(date.today() + timedelta(days=days), time.min, LOCAL)
    lists = usable_lists(service)
    titles = {lst.id: lst.title for lst in lists}
    due = [r for r in open_reminders(service, lists) if due_of(r) is not None and moment(due_of(r)) < cutoff]
    print_json([describe(r, titles) for r in sorted(due, key=by_due)])


def open_command(service, args):
    if len(args) > 1:
        usage()
    lists = usable_lists(service)
    titles = {lst.id: lst.title for lst in lists}
    chosen = [find_list(lists, args[0])] if args else lists
    print_json([describe(r, titles) for r in sorted(open_reminders(service, chosen), key=by_due)])


def thread_tag():
    ident = re.sub(r"[^0-9A-Za-z_-]", "", os.environ.get("BUTLER_THREAD_ID", ""))[:32]
    if not ident:
        return ""
    title = " ".join(os.environ.get("BUTLER_THREAD_TITLE", "").split()).replace('"', "'")[:60]
    return "[thread %s%s] " % (ident, ' "%s"' % title if title else "")


def audit(text):
    """Spools one line for audit/reminders, then has memory-audit commit it in the background; never fails the command."""
    try:
        os.makedirs(os.path.dirname(AUDIT_SPOOL), exist_ok=True)
        with open(AUDIT_SPOOL, "a") as spool:
            fcntl.flock(spool, fcntl.LOCK_EX)
            spool.write("%s\t%s %s%s\n" % (date.today().isoformat(), datetime.now().astimezone().strftime("%H:%M:%S %z"), thread_tag(), " ".join(text.split())))
        subprocess.Popen([MEMORY_AUDIT, "reminders", AUDIT_SPOOL], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL, start_new_session=True)
    except OSError as error:
        print(f"reminders: could not write the audit line: {error}", file=sys.stderr)


def add_command(service, args):
    if len(args) not in (2, 3) or not args[1].strip():
        usage()
    lists = usable_lists(service)
    target = find_list(lists, args[0])
    due_date, all_day = parse_due(args[2]) if len(args) == 3 else (None, False)
    reminder = service.create(
        target.id,
        args[1],
        due_date=due_date,
        all_day=all_day,
        time_zone=None if all_day or due_date is None else str(LOCAL),
    )
    audit('added "%s" to %s, due %s' % (args[1], target.title, args[2] if len(args) == 3 else "none"))
    print_json(describe(reminder, {lst.id: lst.title for lst in lists}))


def complete_command(service, args):
    if len(args) != 1:
        usage()
    reminder = service.get(args[0])
    reminder.completed = True
    reminder.completed_date = datetime.now(timezone.utc)
    service.update(reminder)
    lists = usable_lists(service)
    print_json(describe(reminder, {lst.id: lst.title for lst in lists}))


UPDATE_FLAGS = ("--title", "--due", "--notes", "--flagged")


def parse_update(args):
    """Returns the id and the fields to change, refusing an unknown flag, a repeated one or nothing to change."""
    if not args or args[0].startswith("-"):
        usage()
    ident, rest, changes = args[0], args[1:], {}
    if len(rest) % 2:
        usage()
    for flag, value in zip(rest[0::2], rest[1::2]):
        if flag not in UPDATE_FLAGS or flag in changes:
            usage()
        changes[flag] = value
    if not changes:
        usage()
    if "--title" in changes and not changes["--title"].strip():
        usage()
    if "--flagged" in changes and changes["--flagged"] not in ("yes", "no"):
        usage()
    if "--due" in changes and changes["--due"] != "none":
        parse_due(changes["--due"])
    return ident, changes


def recreate_args(entry):
    """The add command that would bring a deleted reminder back, its due date as add takes it."""
    due = entry.get("due")
    if due and "T" in due:
        due = due[:16]
    return ["add", entry["list"], entry["title"]] + ([due] if due else [])


def update_command(service, args):
    ident, changes = parse_update(args)
    reminder = service.get(ident)
    lists = usable_lists(service)
    titles = {lst.id: lst.title for lst in lists}
    before = describe(reminder, titles)
    if "--title" in changes:
        reminder.title = changes["--title"]
    if "--notes" in changes:
        reminder.desc = changes["--notes"]
    if "--flagged" in changes:
        reminder.flagged = changes["--flagged"] == "yes"
    if "--due" in changes:
        if changes["--due"] == "none":
            reminder.due_date, reminder.all_day, reminder.time_zone = None, False, None
        else:
            reminder.due_date, reminder.all_day = parse_due(changes["--due"])
            reminder.time_zone = None if reminder.all_day else str(LOCAL)
    service.update(reminder)
    after = describe(reminder, titles)
    audit('updated "%s" in %s (id %s): was %s, now %s' % (
        before["title"], before["list"], ident,
        json.dumps({k: before.get(k) for k in ("title", "due", "flagged", "notes")}, ensure_ascii=False),
        json.dumps({k: after.get(k) for k in ("title", "due", "flagged", "notes")}, ensure_ascii=False)))
    print_json({"updated": after, "before": before})


def delete_command(service, args):
    if len(args) != 1 or args[0].startswith("-"):
        usage()
    reminder = service.get(args[0])
    lists = usable_lists(service)
    entry = describe(reminder, {lst.id: lst.title for lst in lists})
    service.delete(reminder)
    audit('deleted "%s" from %s (id %s), due %s, flagged %s, notes %s' % (
        entry["title"], entry["list"], args[0], entry["due"] or "none", entry["flagged"],
        json.dumps(entry.get("notes", ""), ensure_ascii=False)[:500]))
    print_json({"deleted": entry, "recreate": recreate_args(entry)})


COMMANDS = {
    "lists": lists_command,
    "due": due_command,
    "open": open_command,
    "add": add_command,
    "complete": complete_command,
    "update": update_command,
    "delete": delete_command,
}


def main():
    if len(sys.argv) < 2 or sys.argv[1] not in COMMANDS:
        usage()
    command = COMMANDS[sys.argv[1]]
    try:
        command(connect(), sys.argv[2:])
    except (RemindersAuthError, *EXPIRED):
        expired()
    except (RemindersApiError, PyiCloudAPIResponseException, requests.RequestException) as error:
        print(f"iCloud Reminders failed: {error}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
