"""REVL Collingwood's class timetable, read from its public Mindbody schedule widget.

REVL Collingwood is not listed in Mindbody's marketplace search, so its classes
come from the branded schedule widget its own location page embeds, whose page
server-renders the coming week's classes into its React Server Components
payload. That needs no login and holds nothing of Aaron's.
"""

import json
import re
import sys
import urllib.error
import urllib.request
from datetime import date, datetime, timedelta
from zoneinfo import ZoneInfo

WIDGET = "https://go.mindbodyonline.com/book/widgets/schedules/view/f25308655e3/schedule"
STUDIO = "REVL Collingwood"
SITE_ID = 135084
ZONE = ZoneInfo("Australia/Melbourne")
TIMEOUT_SECONDS = 20
EX_USAGE = 64
EX_DATAERR = 65
EX_TEMPFAIL = 75

USAGE = """usage:
  mindbody timetable [today|tomorrow|week|<weekday>|YYYY-MM-DD] [<class name words>]
  mindbody class <class id>
  mindbody link"""

PUSH = re.compile(r'self\.__next_f\.push\(\[1,"((?:[^"\\]|\\.)*)"\]\)')
ROW = re.compile(r"(?m)^([0-9a-f]+):(.*)$")
REF = re.compile(r"^\$([0-9a-f]+)$")
TAG = re.compile(r"<[^>]+>")
CLASS_ID = re.compile(r"^cinst_[A-Za-z0-9]+$")
DAY = re.compile(r"^\d{4}-\d{2}-\d{2}$")
WEEKDAYS = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]


def fail(message, code):
    print(f"mindbody: {message}", file=sys.stderr)
    sys.exit(code)


def fetch():
    request = urllib.request.Request(WIDGET, headers={"User-Agent": "butler-mindbody/1", "Accept": "text/html"})
    try:
        with urllib.request.urlopen(request, timeout=TIMEOUT_SECONDS) as response:
            return response.read().decode("utf-8", "replace")
    except (urllib.error.URLError, TimeoutError, OSError) as error:
        fail(f"could not reach Mindbody's schedule ({error}); try again shortly", EX_TEMPFAIL)


def payload(page):
    chunks = PUSH.findall(page)
    if not chunks:
        fail("Mindbody's schedule page has changed shape: no server payload found", EX_DATAERR)
    return "".join(json.loads(f'"{chunk}"') for chunk in chunks)


def rows(text):
    """The payload's numbered rows, which later classes point at as "$<id>" instead of repeating them."""
    found = {}
    decoder = json.JSONDecoder()
    for match in ROW.finditer(text):
        try:
            found[match.group(1)], _ = decoder.raw_decode(match.group(2))
        except ValueError:
            continue
    return found


def resolve(value, table, depth=0):
    if depth > 8:
        return None
    if isinstance(value, str):
        ref = REF.match(value)
        if ref:
            return resolve(table.get(ref.group(1)), table, depth + 1)
        return None if value == "$undefined" else value
    if isinstance(value, list):
        return [resolve(item, table, depth + 1) for item in value]
    if isinstance(value, dict):
        return {key: resolve(item, table, depth + 1) for key, item in value.items()}
    return value


def classes():
    text = payload(fetch())
    start = text.find('"initialClasses":')
    if start < 0:
        fail("Mindbody's schedule page has changed shape: no classes found", EX_DATAERR)
    data, _ = json.JSONDecoder().raw_decode(text[start + len('"initialClasses":'):])
    table = rows(text)
    out = [resolve(item, table) for item in data.get("classes", [])]
    out.sort(key=lambda item: item.get("startDateTime") or "")
    return out, data.get("toDate")


def when(stamp):
    # Mindbody writes seven fractional digits, which fromisoformat only takes from Python 3.11.
    clean = re.sub(r"\.\d+", "", stamp).replace("Z", "+00:00")
    return datetime.fromisoformat(clean).astimezone(ZONE)


def staff(item):
    names = [person.get("displayLabel") for person in item.get("staff") or [] if isinstance(person, dict)]
    return ", ".join(name for name in names if name) or "coach not listed"


def spots(item):
    if item.get("cancelled"):
        return "cancelled"
    capacity = item.get("capacity")
    left = item.get("availableOnlineBookings")
    if not item.get("bookable") or not item.get("isBookableOnline"):
        opens = item.get("bookingWindowStart")
        if opens and when(opens) > datetime.now(ZONE):
            return f"booking opens {when(opens):%a %-d %b %H:%M}"
        return "not bookable online"
    if left is not None and left <= 0:
        return "full, waitlist open" if item.get("waitlistable") else "full"
    if left is not None and capacity:
        return f"{left} of {capacity} spots free"
    return "bookable"


def line(item):
    start = when(item["startDateTime"])
    restricted = " (members of certain plans only)" if item.get("restrictedToMemberships") else ""
    return (
        f"{start:%a %-d %b %H:%M} {item.get('name', '?')}, {item.get('duration', '?')} min, "
        f"{staff(item)}: {spots(item)}{restricted} [{item.get('id')}]"
    )


def days(word):
    today = datetime.now(ZONE).date()
    word = word.lower()
    if word == "today":
        return today, today
    if word == "tomorrow":
        return today + timedelta(days=1), today + timedelta(days=1)
    if word == "week":
        return today, today + timedelta(days=6)
    if word in WEEKDAYS:
        ahead = (WEEKDAYS.index(word) - today.weekday()) % 7
        return today + timedelta(days=ahead), today + timedelta(days=ahead)
    if DAY.match(word):
        try:
            day = date.fromisoformat(word)
        except ValueError:
            fail(f"not a date: {word}", EX_USAGE)
        return day, day
    return None


def timetable(args):
    span = days(args[0]) if args else None
    words = args[1:] if span else args
    first, last = span or days("week")
    wanted = " ".join(words).lower()
    found, through = classes()

    def fits(item):
        if not item.get("startDateTime") or wanted not in (item.get("name") or "").lower():
            return False
        return first <= when(item["startDateTime"]).date() <= last

    picked = [item for item in found if fits(item)]
    label = f"{first:%a %-d %b}" if first == last else f"{first:%a %-d %b} to {last:%a %-d %b}"
    print(f"{STUDIO}, {label}{', ' + wanted if wanted else ''}:")
    for item in picked:
        print(f"- {line(item)}")
    if not picked:
        print("- no classes listed")
    listed_to = when(found[-1]["startDateTime"]).date() if found else None
    if listed_to and last > listed_to:
        print(f"Mindbody's schedule page lists {len(found)} classes, up to {listed_to:%a %-d %b}; later days may be missing.")
    elif through and last > when(through).date():
        print(f"Mindbody's schedule page only covers up to {when(through):%a %-d %b}.")
    print(f"Times are Melbourne time. Book at {WIDGET}")


def one(class_id):
    if not CLASS_ID.match(class_id):
        fail(f"not a class id: {class_id}", EX_USAGE)
    found, _ = classes()
    for item in found:
        if item.get("id") == class_id:
            print(line(item))
            start, end = when(item["startDateTime"]), when(item["endDateTime"])
            print(f"Runs {start:%H:%M} to {end:%H:%M}, {item.get('numberRegistered', '?')} booked of {item.get('capacity', '?')}.")
            if item.get("bookingWindowStart") and item.get("bookingWindowEnd"):
                print(f"Online booking: {when(item['bookingWindowStart']):%a %-d %b %H:%M} to {when(item['bookingWindowEnd']):%a %-d %b %H:%M}.")
            description = TAG.sub(" ", item.get("description") or "").replace("&nbsp;", " ")
            description = " ".join(description.split())
            if description:
                print(description[:800])
            return
    fail(f"no class {class_id} in the coming week's schedule", EX_DATAERR)


def main():
    args = sys.argv[1:]
    if not args:
        fail(USAGE, EX_USAGE)
    verb, rest = args[0], args[1:]
    if verb == "timetable":
        timetable(rest)
    elif verb == "class" and len(rest) == 1:
        one(rest[0])
    elif verb == "link" and not rest:
        print(f"{STUDIO} (Mindbody site {SITE_ID}) books classes at {WIDGET}")
    else:
        fail(USAGE, EX_USAGE)


main()
