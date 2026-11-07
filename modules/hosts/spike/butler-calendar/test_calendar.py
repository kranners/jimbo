# The calendar's update and delete against a fake Home Assistant, the refusal
# rules, and the uid and recurrence_id the read views print.
# Run: python3 test_calendar.py <butler-calendar dir> <butler-reminders dir>
import importlib.util
import io
import json
import os
import subprocess
import sys
import tempfile
import time
from contextlib import redirect_stdout
from types import SimpleNamespace

HERE, REMINDERS = sys.argv[1], sys.argv[2]
os.environ["TZ"] = "Australia/Melbourne"
time.tzset()


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


edit = load("edit", os.path.join(HERE, "edit.py"))

GYM = {"start": {"dateTime": "2026-11-07T10:00:00+11:00"}, "end": {"dateTime": "2026-11-07T12:30:00+11:00"},
       "summary": "Gym @ Parkhouse", "description": "legs", "location": "Parkhouse", "uid": "gym1@google.com",
       "recurrence_id": None, "rrule": None}
MOVIE = [{"start": {"dateTime": f"2026-11-{d}T19:30:00+11:00"}, "end": {"dateTime": f"2026-11-{d}T22:30:00+11:00"},
          "summary": "Movie", "uid": "movie@google.com", "recurrence_id": f"movie_202611{d}T083000Z",
          "rrule": "FREQ=WEEKLY;BYDAY=WE"} for d in ("11", "18")]
DAY = {"start": {"date": "2026-11-20"}, "end": {"date": "2026-11-21"}, "summary": "Trip", "uid": "trip@google.com"}


class FakeHA:
    def __init__(self, events, name="Aaron", features=3):
        self.events, self.name, self.features, self.calls = events, name, features, []

    def get(self, path, **params):
        if path.startswith("/api/states/"):
            return {"attributes": {"friendly_name": self.name, "supported_features": self.features}}
        return self.events

    def call(self, kind, **fields):
        self.calls.append((kind, fields))


failures = 0


def check(name, condition):
    global failures
    if not condition:
        failures += 1
        print("FAIL", name)
    else:
        print("ok  ", name)


def run(fn, *args):
    audit = tempfile.NamedTemporaryFile(delete=False)
    os.environ["CALENDAR_AUDIT_FILE"] = audit.name
    out = io.StringIO()
    error = None
    with redirect_stdout(out):
        try:
            fn(*args)
        except edit.Refused as e:
            error = str(e)
        except SystemExit as e:
            error = f"exit {e.code}"
    with open(audit.name) as file:
        lines = file.read().splitlines()
    os.unlink(audit.name)
    return out.getvalue(), lines, error


# Parsing.
p = edit.parse_args("delete", ["calendar.aaron", "u1"])
check("delete parses a plain uid", p[:4] == ("calendar.aaron", "u1", None, None))
p = edit.parse_args("delete", ["calendar.aaron", "u1", "r1"])
check("an occurrence defaults to this", p[2:4] == ("r1", "this"))
p = edit.parse_args("delete", ["calendar.aaron", "u1", "r1", "this-and-future", "--named-by-aaron"])
check("this-and-future and the named flag", p[2:4] == ("r1", "this-and-future") and p[5])
try:
    edit.parse_args("delete", ["calendar.aaron", "u1", "this"])
    check("this without a recurrence_id is refused", False)
except edit.Refused:
    check("this without a recurrence_id is refused", True)
p = edit.parse_args("update", ["calendar.aaron", "u1", "--summary", "Gym", "--start", "2026-11-08T09:00"])
check("update parses flags", p[4]["summary"] == "Gym" and p[4]["start"].hour == 9 and p[4]["start"].tzinfo)
check("an unknown flag is usage", run(edit.parse_args, "update", ["calendar.aaron", "u1", "--colour", "red"])[2] == "exit 2")
check("a bad entity is usage", run(edit.parse_args, "delete", ["aaron", "u1"])[2] == "exit 2")
check("a bad time is usage", run(edit.parse_args, "update", ["calendar.aaron", "u1", "--start", "tomorrow"])[2] == "exit 2")

# Refusals.
check("the work calendar is refused", run(edit.check_writable, "calendar.work", "Work", True)[2])
check("a muted calendar is refused", run(edit.check_writable, "calendar.seido_karate", "Seido karate", False)[2])
check("a muted calendar named by Aaron is allowed", not run(edit.check_writable, "calendar.seido_karate", "Seido karate", True)[2])
check("a timetable is muted", run(edit.check_writable, "calendar.x", "Swinburne timetable", False)[2])
check("a personal calendar is writable", not run(edit.check_writable, "calendar.aaronpierce114_gmail_com", "aaronpierce114@gmail.com", False)[2])
ha = FakeHA([GYM], name="Work timetable")
check("delete on the work calendar changes nothing", run(edit.delete, ha, ["calendar.timetable", "gym1@google.com", "--named-by-aaron"])[2] and not ha.calls)
ha = FakeHA([GYM], name="School holidays")
check("delete on a muted calendar changes nothing", run(edit.delete, ha, ["calendar.school", "gym1@google.com"])[2] and not ha.calls)

# Deleting a one-off prints it whole and audits it.
ha = FakeHA([GYM])
out, audit, error = run(edit.delete, ha, ["calendar.aaron", "gym1@google.com"])
check("delete a one-off", not error and ha.calls == [("calendar/event/delete", {"entity_id": "calendar.aaron", "uid": "gym1@google.com"})])
check("delete prints the event's details", '"description": "legs"' in out and "calendar create calendar.aaron 'Gym @ Parkhouse'" in out)
check("delete audits summary and times", len(audit) == 1 and "Gym @ Parkhouse" in audit[0] and "2026-11-07T10:00:00+11:00" in audit[0] and "legs" in audit[0])
check("series on a one-off is refused", run(edit.delete, FakeHA([GYM]), ["calendar.aaron", "gym1@google.com", "series"])[2])
check("the work calendar is refused by name", run(edit.check_writable, "calendar.aaron_work", "Aaron work", True)[2])
check("an unknown uid changes nothing", run(edit.delete, FakeHA([GYM]), ["calendar.aaron", "nope"])[2])

# Recurring.
ha = FakeHA(MOVIE)
out, audit, error = run(edit.delete, ha, ["calendar.aaron", "movie@google.com"])
check("a recurring uid alone is refused", error and "series" in error and not ha.calls)
out, audit, error = run(edit.delete, ha, ["calendar.aaron", "movie@google.com", "series"])
check("a series delete echoes the summary", 'whole recurring series "Movie"' in out and "2 of them" in out and "series" in audit[0])
check("a series delete sends no occurrence", ha.calls[0][1] == {"entity_id": "calendar.aaron", "uid": "movie@google.com"})
ha = FakeHA(MOVIE)
out, audit, error = run(edit.delete, ha, ["calendar.aaron", "movie@google.com", "movie_20261118T083000Z", "this-and-future"])
check("this-and-future", ha.calls[0][1].get("recurrence_range") == "THISANDFUTURE" and "2026-11-18T19:30" in out)
ha = FakeHA(MOVIE)
run(edit.delete, ha, ["calendar.aaron", "movie@google.com", "movie_20261111T083000Z"])
check("one occurrence", ha.calls[0][1] == {"entity_id": "calendar.aaron", "uid": "movie@google.com", "recurrence_id": "movie_20261111T083000Z"})
ha = FakeHA(MOVIE)
check("updating a whole series is refused", run(edit.update, ha, ["calendar.aaron", "movie@google.com", "--summary", "Film"], "")[2] and not ha.calls)

# Updates: Google's calendars make the new event, then delete the old.
ha = FakeHA([GYM])
out, audit, error = run(edit.update, ha, ["calendar.aaron", "gym1@google.com", "--start", "2026-11-08T09:00"], "")
check("update replaces on a calendar without update", not error and [c[0] for c in ha.calls] == ["calendar/event/create", "calendar/event/delete"])
made = ha.calls[0][1]["event"]
check("moving the start keeps the length", made["dtstart"] == "2026-11-08T09:00:00+11:00" and made["dtend"] == "2026-11-08T11:30:00+11:00")
check("update keeps description and location", made.get("description") == "legs" and made.get("location") == "Parkhouse")
check("update audits before and after", "was 2026-11-07T10:00:00+11:00" in audit[0] and "now \"Gym @ Parkhouse\" 2026-11-08T09:00" in audit[0])
ha = FakeHA([GYM], features=7)
run(edit.update, ha, ["calendar.aaron", "gym1@google.com", "--summary", "Gym"], "new notes")
check("update in place when the calendar can", ha.calls[0][0] == "calendar/event/update" and ha.calls[0][1]["event"]["description"] == "new notes")
ha = FakeHA([DAY])
run(edit.update, ha, ["calendar.aaron", "trip@google.com", "--start", "2026-11-22"], "")
check("an all-day event stays all-day", ha.calls[0][1]["event"]["dtstart"] == "2026-11-22" and ha.calls[0][1]["event"]["dtend"] == "2026-11-23")
ha = FakeHA([GYM])
check("an end before the start is refused", run(edit.update, ha, ["calendar.aaron", "gym1@google.com", "--end", "2026-11-07T09:00"], "")[2] and not ha.calls)
ha = FakeHA([GYM])
check("mixing a date and a time is refused", run(edit.update, ha, ["calendar.aaron", "gym1@google.com", "--end", "2026-11-09"], "")[2] and not ha.calls)

# The read views print uid and recurrence_id.
raw = json.dumps([GYM, MOVIE[0]])
events = subprocess.run(["jq", "--arg", "calendar", "calendar.aaron", "--from-file", os.path.join(HERE, "events.jq")],
                        input=raw, capture_output=True, text=True, check=True).stdout
table = subprocess.run(["jq", "--slurp", "--raw-output", "--from-file", os.path.join(HERE, "tabulate.jq")],
                       input=events, capture_output=True, text=True, check=True).stdout.splitlines()
check("events prints the uid", table[0].split("\t")[5] == "gym1@google.com" and table[0].split("\t")[6] == "")
check("events prints an occurrence's recurrence_id", table[1].split("\t")[6] == "movie_20261111T083000Z")

# Reminders' update and delete.
reminders = load("reminders", os.path.join(REMINDERS, "reminders.py"))
ident, changes = reminders.parse_update(["R1", "--title", "Bins", "--due", "none"])
check("reminders update parses", ident == "R1" and changes == {"--title": "Bins", "--due": "none"})
for bad in (["R1"], ["R1", "--colour", "red"], ["R1", "--flagged", "maybe"], ["R1", "--due", "friday"], ["--title", "x"]):
    try:
        with redirect_stdout(io.StringIO()):
            reminders.parse_update(bad)
        check(f"reminders update refuses {bad}", False)
    except SystemExit:
        check(f"reminders update refuses {bad}", True)


class FakeReminders:
    def __init__(self):
        self.item = SimpleNamespace(id="R1", list_id="L1", title="Call dentist", desc="", due_date=None, all_day=False,
                                    time_zone=None, completed=False, flagged=False, deleted=False)
        self.updated = self.deleted = None

    def get(self, ident):
        return self.item

    def lists(self):
        return [SimpleNamespace(id="L1", title="Inbox", deleted=False, is_group=False)]

    def update(self, item):
        self.updated = item

    def delete(self, item):
        self.deleted = item


audited = []
reminders.audit = audited.append
service = FakeReminders()
with redirect_stdout(io.StringIO()) as out:
    reminders.update_command(service, ["R1", "--due", "2026-11-09T09:30", "--flagged", "yes"])
check("reminders update sets due, zone and flag", service.updated.due_date.hour == 9 and service.updated.time_zone and service.updated.flagged)
check("reminders update audits", "Call dentist" in audited[-1] and "2026-11-09T09:30" in audited[-1])
service = FakeReminders()
with redirect_stdout(io.StringIO()) as out:
    reminders.delete_command(service, ["R1"])
result = json.loads(out.getvalue())
check("reminders delete prints how to bring it back", service.deleted and result["recreate"] == ["add", "Inbox", "Call dentist"])
check("reminders delete audits", "deleted \"Call dentist\"" in audited[-1])

sys.exit(1 if failures else 0)
