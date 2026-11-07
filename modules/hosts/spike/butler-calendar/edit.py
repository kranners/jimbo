# Updates and deletes events on Aaron's personal calendars through Home
# Assistant, and says whether a calendar may be written at all.
# Reads go through Home Assistant's REST API and writes through its websocket
# API, the only one that deletes. Google's integration cannot update an event,
# so an update there makes the changed event and then deletes the original.
# The token is read from HOME_ASSISTANT_TOKEN_FILE and never printed; the audit
# line for each change goes to the file CALENDAR_AUDIT_FILE names, which the
# calendar wrapper spools to audit/calendar.
import json
import os
import re
import shlex
import sys
import urllib.error
import urllib.parse
import urllib.request
from datetime import date, datetime, timedelta

HTTP = "http://127.0.0.1:8123"
WS = "ws://127.0.0.1:8123/api/websocket"
UPDATE_EVENT = 4  # CalendarEntityFeature.UPDATE_EVENT

USAGE = """usage: calendar update <calendar.entity> <uid> [<recurrence_id>] [--summary S] [--start T] [--end T] [--location L] [--named-by-aaron]  (new description on stdin)
       calendar delete <calendar.entity> <uid> [<recurrence_id> [this|this-and-future] | series] [--named-by-aaron]
uid and recurrence_id come from calendar events or agenda; dates are YYYY-MM-DD or YYYY-MM-DDTHH:MM"""

# Aaron's work calendar is read-only, whatever is said.
READ_ONLY = re.compile(r"\bwork\b")
# Calendars Aaron asked to be muted, which are written only when he names one.
MUTED = re.compile(r"karate|seido|swinburne|timetable|school")

ENTITY = re.compile(r"calendar\.[a-z0-9_]+")
INSTANT = re.compile(r"\d{4}-\d{2}-\d{2}(T\d{2}:\d{2}(:\d{2})?([+-]\d{2}:\d{2}|Z)?)?")


class Refused(Exception):
    pass


def usage():
    print(USAGE, file=sys.stderr)
    sys.exit(2)


def words(*texts):
    return " ".join(t.lower().replace("_", " ").replace(".", " ") for t in texts if t)


def check_writable(entity, name, named):
    """Refuses the work calendar always, and a muted one unless Aaron named it."""
    text = words(entity, name)
    if READ_ONLY.search(text):
        raise Refused(f"{entity} ({name}) is Aaron's work calendar, which stays read-only")
    if MUTED.search(text) and not named:
        raise Refused(
            f"{entity} ({name}) is one of the calendars Aaron muted; pass --named-by-aaron "
            "only when Aaron named this calendar himself"
        )


def parse_instant(text):
    """A date, or a time with its offset, local time when none is given."""
    if not INSTANT.fullmatch(text):
        usage()
    try:
        if "T" not in text:
            return date.fromisoformat(text)
        value = datetime.fromisoformat(text.replace("Z", "+00:00"))
    except ValueError:
        usage()
    return value if value.tzinfo else value.astimezone()


def read_value(text):
    if "T" in text:
        return datetime.fromisoformat(text.replace("Z", "+00:00"))
    return date.fromisoformat(text)


def shown(value):
    return value.isoformat()


def parse_args(verb, args):
    """Returns entity, uid, recurrence_id, range, changes and named from update's or delete's arguments."""
    named = "--named-by-aaron" in args
    args = [a for a in args if a != "--named-by-aaron"]
    if len(args) < 2 or not ENTITY.fullmatch(args[0]) or not args[1] or args[1].startswith("-"):
        usage()
    entity, uid, rest = args[0], args[1], args[2:]
    recurrence_id = None
    if verb == "delete" and rest == ["series"]:
        return entity, uid, None, "series", {}, named
    if rest and not rest[0].startswith("-"):
        recurrence_id, rest = rest[0], rest[1:]
    changes, scope = {}, None
    if verb == "delete":
        if recurrence_id == "series":
            usage()
        if rest and rest[0] in ("this", "this-and-future") and recurrence_id:
            scope, rest = rest[0], rest[1:]
        elif recurrence_id in ("this", "this-and-future"):
            raise Refused("this and this-and-future need the occurrence's recurrence_id first, from calendar events")
        if rest:
            usage()
        if recurrence_id and not scope:
            scope = "this"
    else:
        if len(rest) % 2:
            usage()
        for flag, value in zip(rest[0::2], rest[1::2]):
            key = {"--summary": "summary", "--start": "start", "--end": "end", "--location": "location"}.get(flag)
            if key is None or key in changes:
                usage()
            changes[key] = parse_instant(value) if key in ("start", "end") else value
        if "summary" in changes and not changes["summary"].strip():
            usage()
    return entity, uid, recurrence_id, scope, changes, named


def merge(event, changes, description):
    """The event as it will be after an update, keeping its length when only the start moves."""
    start, end = read_value(event["start"]), read_value(event["end"])
    new_start, new_end = changes.get("start", start), changes.get("end")
    if new_end is None:
        if "start" in changes and isinstance(new_start, datetime) == isinstance(start, datetime):
            new_end = new_start + (end - start)
        elif "start" in changes:
            new_end = new_start + (timedelta(hours=1) if isinstance(new_start, datetime) else timedelta(days=1))
        else:
            new_end = end
    if isinstance(new_start, datetime) != isinstance(new_end, datetime):
        raise Refused("start and end must both be dates, for an all-day event, or both times")
    if new_end <= new_start:
        raise Refused("the end must come after the start")
    merged = {
        "summary": changes.get("summary", event.get("summary") or ""),
        "dtstart": shown(new_start),
        "dtend": shown(new_end),
    }
    new_description = description if description else event.get("description")
    if new_description:
        merged["description"] = new_description
    location = changes.get("location", event.get("location"))
    if location:
        merged["location"] = location
    return merged


def details(entity, event):
    """Everything about an event needed to bring it back, one JSON line."""
    keep = ("summary", "start", "end", "location", "description", "rrule", "uid", "recurrence_id")
    return json.dumps({"calendar": entity, **{k: event[k] for k in keep if event.get(k)}}, ensure_ascii=False)


def recreate(entity, event):
    return "calendar create " + " ".join(
        shlex.quote(a) for a in (entity, event.get("summary") or "", event["start"], event["end"])
    )


def flat(text, limit=300):
    return " ".join(str(text).split())[:limit]


class HomeAssistant:
    def __init__(self):
        with open(os.environ["HOME_ASSISTANT_TOKEN_FILE"]) as file:
            self.token = file.read().strip()
        self.socket = None
        self.next_id = 1

    def get(self, path, **params):
        query = ("?" + urllib.parse.urlencode(params)) if params else ""
        request = urllib.request.Request(HTTP + path + query, headers={"Authorization": f"Bearer {self.token}"})
        with urllib.request.urlopen(request, timeout=30) as reply:
            return json.load(reply)

    def call(self, kind, **fields):
        if self.socket is None:
            from websockets.sync.client import connect

            self.socket = connect(WS, max_size=2**24)
            self.socket.recv()
            self.socket.send(json.dumps({"type": "auth", "access_token": self.token}))
            if json.loads(self.socket.recv()).get("type") != "auth_ok":
                raise Refused("Home Assistant refused the token")
        self.next_id += 1
        self.socket.send(json.dumps({"id": self.next_id, "type": kind, **fields}))
        while True:
            reply = json.loads(self.socket.recv())
            if reply.get("id") == self.next_id and reply.get("type") == "result":
                break
        if not reply.get("success"):
            raise Refused(f"Home Assistant refused {kind}: {reply.get('error', {}).get('message')}")
        return reply.get("result")


def calendar_state(ha, entity):
    try:
        state = ha.get(f"/api/states/{entity}")
    except urllib.error.HTTPError as error:
        if error.code == 404:
            raise Refused(f"no calendar {entity}; see calendar calendars")
        raise
    attributes = state.get("attributes", {})
    return attributes.get("friendly_name", ""), int(attributes.get("supported_features") or 0)


def find(ha, entity, uid, recurrence_id):
    """The event with that uid, the occurrence with that recurrence_id, and whether it recurs."""
    today = date.today()
    window = dict(start=shown(today - timedelta(days=180)), end=shown(today + timedelta(days=400)))
    events = [e for e in ha.get(f"/api/calendars/{entity}", **window) if e.get("uid") == uid]
    if not events:
        raise Refused(f"no event with uid {uid} on {entity} from {window['start']} to {window['end']}; check calendar events")
    events = [flatten(e) for e in events]
    recurring = any(e.get("rrule") or e.get("recurrence_id") for e in events)
    occurrences = [e["start"] for e in events]
    if recurrence_id:
        events = [e for e in events if e.get("recurrence_id") == recurrence_id]
        if not events:
            raise Refused(f"event {uid} has no occurrence {recurrence_id}; check calendar events")
    return events[0], recurring, occurrences


def flatten(event):
    event = dict(event)
    for key in ("start", "end"):
        if isinstance(event.get(key), dict):
            event[key] = event[key].get("dateTime") or event[key].get("date")
    return event


def is_copy(event, merged, uid):
    """Whether a listed event is the changed copy update just made."""
    return (event.get("summary") == merged["summary"] and event.get("uid") != uid and read_value(event["start"]) == read_value(merged["dtstart"]) and read_value(event["end"]) == read_value(merged["dtend"]))


def audit(line):
    path = os.environ.get("CALENDAR_AUDIT_FILE")
    if path:
        with open(path, "a") as file:
            file.write(line + "\n")


def delete(ha, args):
    entity, uid, recurrence_id, scope, _, named = parse_args("delete", args)
    name, _ = calendar_state(ha, entity)
    check_writable(entity, name, named)
    event, recurring, occurrences = find(ha, entity, uid, recurrence_id)
    summary = event.get("summary") or ""
    if recurring and not recurrence_id and scope != "series":
        raise Refused(
            f'"{summary}" recurs, {len(occurrences)} occurrences from {occurrences[0]} in the next year or so; '
            "pass one occurrence's recurrence_id from calendar events, or the word series to delete every occurrence"
        )
    if scope == "series" and not recurring:
        raise Refused(f'"{summary}" does not recur; delete it without the word series')
    fields = {"entity_id": entity, "uid": uid}
    if recurrence_id:
        fields["recurrence_id"] = recurrence_id
    if scope == "this-and-future":
        fields["recurrence_range"] = "THISANDFUTURE"
    ha.call("calendar/event/delete", **fields)
    if scope == "series":
        what = f'the whole recurring series "{summary}"'
        print(f'Deleted the whole recurring series "{summary}" on {entity}, every occurrence, '
              f'{len(occurrences)} of them seen from {occurrences[0]} to {occurrences[-1]}'
              f'{", rule " + event["rrule"] if event.get("rrule") else ""}')
    elif scope == "this-and-future":
        what = f'"{summary}" from {event["start"]} on'
        print(f'Deleted "{summary}" on {entity} from the occurrence at {event["start"]} onwards')
    else:
        what = f'"{summary}"'
        print(f'Deleted "{summary}" on {entity} from {event["start"]} to {event["end"]}')
    print("Deleted event:", details(entity, event))
    if not recurring:
        print("To bring it back:", recreate(entity, event), "with its description on stdin")
    audit(f"deleted {what} on {entity} from {event['start']} to {event['end']}"
          f"{f', {len(occurrences)} occurrences seen' if scope == 'series' else ''}: {details(entity, event)}")


def update(ha, args, description):
    entity, uid, recurrence_id, _, changes, named = parse_args("update", args)
    if not changes and not description:
        usage()
    name, features = calendar_state(ha, entity)
    check_writable(entity, name, named)
    event, recurring, _ = find(ha, entity, uid, recurrence_id)
    if recurring and not recurrence_id:
        raise Refused("that event recurs; update one occurrence by its recurrence_id from calendar events")
    merged = merge(event, changes, description)
    if features & UPDATE_EVENT:
        fields = {"entity_id": entity, "uid": uid, "event": merged}
        if recurrence_id:
            fields["recurrence_id"] = recurrence_id
        ha.call("calendar/event/update", **fields)
        how, new_uid = "in place", uid
    else:
        # Google's calendars cannot update, so make the changed event, then remove the original.
        ha.call("calendar/event/create", entity_id=entity, event=merged)
        fields = {"entity_id": entity, "uid": uid}
        if recurrence_id:
            fields["recurrence_id"] = recurrence_id
        try:
            ha.call("calendar/event/delete", **fields)
        except Exception as error:
            audit(f'made a changed copy of "{flat(event.get("summary") or "", 120)}" on {entity} but could not delete the original, so both are there: '
                  f"original {details(entity, event)}, copy {json.dumps(merged, ensure_ascii=False)}")
            raise Refused(f"made the changed event but could not delete the original, so both are there now: {error}")
        how = "as a new event replacing the original, so any invitees, colour or reminders on the original are gone"
        new_uid = None
        try:
            found = ha.get(f"/api/calendars/{entity}", start=merged["dtstart"], end=merged["dtend"])
            same = [e.get("uid") for e in map(flatten, found) if is_copy(e, merged, uid)]
            new_uid = same[0] if len(same) == 1 else None
        except Exception:
            pass
        if recurrence_id:
            how += "; the occurrence now stands alone, outside its series"
    print(f'Updated "{merged["summary"]}" on {entity}, now {merged["dtstart"]} to {merged["dtend"]}, {how}')
    print("Before:", details(entity, event))
    print("After:", json.dumps({"calendar": entity, **merged, **({"uid": new_uid} if new_uid else {})}, ensure_ascii=False))
    audit(f'updated "{flat(event.get("summary") or "", 120)}" on {entity} {how.split(",")[0]}: was {event["start"]} to {event["end"]}, '
          f'now "{flat(merged["summary"], 120)}" {merged["dtstart"]} to {merged["dtend"]}; '
          f"before {details(entity, event)}; after {json.dumps({**merged, **({'uid': new_uid} if new_uid else {})}, ensure_ascii=False)}")


def main(argv):
    if not argv:
        usage()
    verb, args = argv[0], argv[1:]
    try:
        if verb == "writable" and len(args) in (1, 2) and ENTITY.fullmatch(args[0]):
            if len(args) == 2 and args[1] != "--named-by-aaron":
                usage()
            name, _ = calendar_state(HomeAssistant(), args[0])
            check_writable(args[0], name, len(args) == 2)
        elif verb == "delete":
            delete(HomeAssistant(), args)
        elif verb == "update":
            description = sys.stdin.read() if not sys.stdin.isatty() else ""
            update(HomeAssistant(), args, description.strip())
        else:
            usage()
    except Refused as error:
        print(f"calendar: {error}", file=sys.stderr)
        sys.exit(77)
    except Exception as error:
        print(f"calendar: Home Assistant failed: {error}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main(sys.argv[1:])
