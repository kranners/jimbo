import json
import os
import re
import sys
from datetime import date, datetime, time, timedelta, timezone

os.environ.setdefault("PYTHON_KEYRING_BACKEND", "keyring.backends.null.Keyring")

from pyicloud import PyiCloudService
from pyicloud.exceptions import (
    PyiCloud2FARequiredException,
    PyiCloud2SARequiredException,
    PyiCloudAuthRequiredException,
    PyiCloudFailedLoginException,
    PyiCloudNoStoredPasswordAvailableException,
    PyiCloudServiceUnavailable,
)
from tzlocal import get_localzone

COOKIE_DIRECTORY = "/var/lib/butler/.local/share/pyicloud"
APPLE_ID_FILE = os.path.join(COOKIE_DIRECTORY, "apple-id")
EX_TEMPFAIL = 75
LOCAL = get_localzone()

USAGE = """usage: reminders lists
       reminders due [days]
       reminders open [list title]
       reminders add <list title> <title> [YYYY-MM-DD[THH:MM]]
       reminders complete <id>"""

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


COMMANDS = {
    "lists": lists_command,
    "due": due_command,
    "open": open_command,
    "add": add_command,
    "complete": complete_command,
}


def main():
    if len(sys.argv) < 2 or sys.argv[1] not in COMMANDS:
        usage()
    command = COMMANDS[sys.argv[1]]
    command(connect(), sys.argv[2:])


main()
