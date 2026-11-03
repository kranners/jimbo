import fcntl
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

PLACES = "https://places.googleapis.com/v1/places:searchText"
ROUTES = "https://routes.googleapis.com/directions/v2:computeRoutes"
SECRET = "/var/lib/secrets/butler-google-maps-api-key"
STATE = "/var/lib/butler/.local/state/maps"
ZONE = ZoneInfo("Australia/Melbourne")
TIMEOUT_SECONDS = 20
EX_TEMPFAIL = 75
EX_CONFIG = 78

# Calls a month, kept under Google's free monthly usage: a text search that reads opening
# hours bills as Places Text Search Enterprise, 1,000 free, and a route without traffic as
# Compute Routes Essentials, 10,000 free.
LIMITS = {"places": 900, "routes": 5000}

# Melbourne's CBD, so a search without an area prefers places around Melbourne.
MELBOURNE = {"latitude": -37.8136, "longitude": 144.9631}

# Reading opening hours, the phone number or the rating is what bills the Enterprise SKU;
# reviews and descriptions, the Atmosphere fields, are never asked for.
PLACE_FIELDS = ",".join(
    "places." + field
    for field in [
        "id",
        "displayName",
        "primaryTypeDisplayName",
        "formattedAddress",
        "nationalPhoneNumber",
        "rating",
        "userRatingCount",
        "websiteUri",
        "googleMapsUri",
        "businessStatus",
        "currentOpeningHours",
    ]
)

SEARCH_FIELDS = ",".join(
    "places." + field
    for field in [
        "id",
        "displayName",
        "primaryTypeDisplayName",
        "formattedAddress",
        "rating",
        "userRatingCount",
        "businessStatus",
        "currentOpeningHours.openNow",
    ]
)

ROUTE_FIELDS = ",".join(
    [
        "routes.duration",
        "routes.distanceMeters",
        "routes.description",
        "routes.warnings",
        "routes.legs.steps.distanceMeters",
        "routes.legs.steps.staticDuration",
        "routes.legs.steps.travelMode",
        "routes.legs.steps.navigationInstruction.instructions",
        "routes.legs.steps.transitDetails",
    ]
)

MODES = {
    "walk": "WALK",
    "bike": "BICYCLE",
    "drive": "DRIVE",
    "transit": "TRANSIT",
}

LINK = re.compile(
    r"^https://(maps\.app\.goo\.gl/|goo\.gl/maps/|(www\.)?google\.[a-z.]+/maps|maps\.google\.[a-z.]+/)"
)
GOOGLE_HOST = re.compile(r"^((www|maps|consent)\.)?google\.[a-z.]+$|^maps\.app\.goo\.gl$|^goo\.gl$")
LATLNG = re.compile(r"^(-?\d{1,2}(\.\d+)?),\s*(-?\d{1,3}(\.\d+)?)$")

USAGE = """usage: maps place <maps link | name and area>
       maps search <query>... [near <place>] [open]
       maps route <walk|bike|drive|transit> <from> <to> [depart|arrive <time>]
a place is a Google Maps link, an address, a name and area, lat,lng or place_id:ID;
a time is HH:MM today or YYYY-MM-DD HH:MM, Melbourne time"""


def usage():
    print(USAGE, file=sys.stderr)
    sys.exit(2)


def fail(message, status=1):
    print(f"maps: {message}", file=sys.stderr)
    sys.exit(status)


def clean(text, limit=300):
    """Text from Maps is someone else's: one line, no control characters, bounded."""
    text = re.sub(r"[\x00-\x1f\x7f]+", " ", str(text)).strip()
    return text if len(text) <= limit else text[: limit - 1] + "…"


def api_key():
    directory = os.environ.get("CREDENTIALS_DIRECTORY")
    key = ""
    if directory:
        try:
            with open(os.path.join(directory, "google-maps-api-key")) as file:
                key = file.read().strip()
        except FileNotFoundError:
            pass
    if not key:
        fail(f"no Google Maps API key yet; Aaron has to write one to {SECRET} on spike and restart butler", EX_CONFIG)
    return key


def spend(kind):
    """Counts this month's calls of a kind, refusing past its limit."""
    os.makedirs(STATE, mode=0o700, exist_ok=True)
    month = datetime.now(ZONE).strftime("%Y-%m")
    path = os.path.join(STATE, "usage.json")
    with open(os.path.join(STATE, "usage.lock"), "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            with open(path) as file:
                usage = json.load(file)
        except (FileNotFoundError, ValueError):
            usage = {}
        if usage.get("month") != month:
            usage = {"month": month}
        used = usage.get(kind, 0)
        if used >= LIMITS[kind]:
            fail(f"this month's {LIMITS[kind]} {kind} lookups are used up; it resets on the 1st", EX_TEMPFAIL)
        usage[kind] = used + 1
        with open(path + ".new", "w") as file:
            json.dump(usage, file)
        os.replace(path + ".new", path)


def post(url, fields, body, kind):
    key = api_key()
    spend(kind)
    request = urllib.request.Request(
        url,
        data=json.dumps(body).encode(),
        method="POST",
        headers={
            "Content-Type": "application/json",
            "X-Goog-Api-Key": key,
            "X-Goog-FieldMask": fields,
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=TIMEOUT_SECONDS) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        try:
            message = json.load(error).get("error", {}).get("message", "")
        except ValueError:
            message = ""
        fail(f"Google answered HTTP {error.code}: {clean(message) or error.reason}")
    except (urllib.error.URLError, TimeoutError) as error:
        fail(f"could not reach Google: {error}", EX_TEMPFAIL)


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


def follow(link):
    """Follows a share link's redirects, staying on Google, to the full Maps URL."""
    opener = urllib.request.build_opener(NoRedirect)
    url = link
    for _ in range(6):
        parsed = urllib.parse.urlsplit(url)
        if parsed.scheme != "https" or not GOOGLE_HOST.match(parsed.hostname or ""):
            fail("that link leads off Google Maps")
        query = urllib.parse.parse_qs(parsed.query)
        if parsed.hostname.startswith("consent.") and "continue" in query:
            url = query["continue"][0]
            continue
        if not parsed.hostname.endswith("goo.gl"):
            return parsed
        request = urllib.request.Request(url, headers={"User-Agent": "curl/8"})
        try:
            with opener.open(request, timeout=TIMEOUT_SECONDS):
                fail("that short link did not lead to a place")
        except urllib.error.HTTPError as error:
            if error.code not in (301, 302, 303, 307, 308) or not error.headers.get("Location"):
                fail(f"that short link answered HTTP {error.code}")
            url = urllib.parse.urljoin(url, error.headers["Location"])
        except (urllib.error.URLError, TimeoutError) as error:
            fail(f"could not open that link: {error}", EX_TEMPFAIL)
    fail("that link redirected too many times")


def latlng(text):
    match = LATLNG.match(text.strip())
    if match:
        return {"latitude": float(match[1]), "longitude": float(match[3])}
    return None


def resolve_link(link):
    """A Maps link's place as (text, point), either possibly None."""
    parsed = follow(link)
    query = urllib.parse.parse_qs(parsed.query)
    path = urllib.parse.unquote_plus(parsed.path)
    at = re.search(r"/@(-?\d+\.\d+),(-?\d+\.\d+)", path)
    point = {"latitude": float(at[1]), "longitude": float(at[2])} if at else None
    for name in ("q", "query", "destination"):
        if name in query:
            text = query[name][0]
            return (None, latlng(text)) if latlng(text) else (text, point)
    named = re.search(r"/maps/(?:place|search)/([^/@]+)", path)
    if named:
        return named[1], point
    if point:
        return None, point
    fail("could not find a place in that link")


def where(text):
    """A place argument as (text, point), resolving Maps links."""
    text = text.strip()
    if LINK.match(text):
        return resolve_link(text)
    if latlng(text):
        return None, latlng(text)
    return text, None


def local(timestamp):
    moment = datetime.fromisoformat(timestamp.replace("Z", "+00:00")).astimezone(ZONE)
    today = datetime.now(ZONE).date()
    if moment.date() == today:
        return moment.strftime("%-I:%M %p today")
    if moment.date() == today + timedelta(days=1):
        return moment.strftime("%-I:%M %p tomorrow")
    return moment.strftime("%-I:%M %p %a %-d %b")


def status(place):
    business = place.get("businessStatus")
    if business == "CLOSED_PERMANENTLY":
        return "permanently closed"
    if business == "CLOSED_TEMPORARILY":
        return "temporarily closed"
    hours = place.get("currentOpeningHours")
    if not hours or "openNow" not in hours:
        return "hours unknown"
    if hours["openNow"]:
        closes = hours.get("nextCloseTime")
        return "open now" + (f", closes {local(closes)}" if closes else "")
    opens = hours.get("nextOpenTime")
    return "closed now" + (f", opens {local(opens)}" if opens else "")


def name(place):
    return clean(place.get("displayName", {}).get("text", "unnamed"), 120)


def rating(place):
    if "rating" not in place:
        return "no rating"
    return f"{place['rating']}★ from {place.get('userRatingCount', 0)}"


def text_search(query, fields, size, point=None, open_now=False):
    body = {
        "textQuery": query,
        "languageCode": "en-AU",
        "regionCode": "au",
        "pageSize": size,
        "locationBias": {
            "circle": {
                "center": point or MELBOURNE,
                "radius": 500.0 if point else 50000.0,
            }
        },
    }
    if open_now:
        body["openNow"] = True
    return post(PLACES, fields, body, "places").get("places", [])


def place(args):
    if not args:
        usage()
    text, point = where(" ".join(args))
    if text and text.startswith("place_id:"):
        fail("give a name and area or a link; a place_id only works as a route's end")
    if text is None:
        text = f"{point['latitude']},{point['longitude']}"
    found = text_search(text, PLACE_FIELDS, 3, point)
    if not found:
        fail("Google Maps found no place for that")
    best = found[0]
    print(f"now: {datetime.now(ZONE).strftime('%a %-d %b %Y %-I:%M %p')} Melbourne time")
    print(f"place: {name(best)}" + (f" ({clean(best['primaryTypeDisplayName']['text'], 60)})" if best.get("primaryTypeDisplayName") else ""))
    print(f"status: {status(best)}")
    print(f"address: {clean(best.get('formattedAddress', 'unknown'))}")
    print(f"phone: {clean(best.get('nationalPhoneNumber', 'none listed'), 40)}")
    print(f"rating: {rating(best)}")
    if best.get("websiteUri"):
        print(f"website: {clean(best['websiteUri'])}")
    print(f"maps: {clean(best.get('googleMapsUri', ''))}")
    print(f"place_id: {best['id']}")
    days = best.get("currentOpeningHours", {}).get("weekdayDescriptions", [])
    if days:
        print("hours this week:")
        for day in days:
            print(f"  {clean(day, 120)}")
    if len(found) > 1:
        print("other matches:")
        for other in found[1:]:
            print(f"  {name(other)}, {clean(other.get('formattedAddress', ''))}")


def search(args):
    open_now = False
    if args and args[-1] == "open":
        open_now = True
        args = args[:-1]
    near = None
    if "near" in args:
        index = args.index("near")
        if index == 0 or index != len(args) - 2:
            usage()
        near = args[index + 1]
        args = args[:index]
    if not args:
        usage()
    query = " ".join(args)
    point = None
    if near:
        text, point = where(near)
        if text and not point:
            query = f"{query} near {text}"
    found = text_search(query, SEARCH_FIELDS, 8, point, open_now)
    if not found:
        print("no places found")
        return
    for each in found:
        kind = f" ({clean(each['primaryTypeDisplayName']['text'], 60)})" if each.get("primaryTypeDisplayName") else ""
        print(f"{name(each)}{kind} | {clean(each.get('formattedAddress', ''))} | {rating(each)} | {status(each)}")


def waypoint(text):
    if text.startswith("place_id:"):
        identifier = text.removeprefix("place_id:")
        if not re.fullmatch(r"[A-Za-z0-9_-]{10,300}", identifier):
            usage()
        return {"placeId": identifier}
    text, point = where(text)
    if point:
        return {"location": {"latLng": point}}
    return {"address": text}


def when(text):
    now = datetime.now(ZONE)
    try:
        if re.fullmatch(r"\d{1,2}:\d{2}", text):
            moment = datetime.strptime(text, "%H:%M").replace(year=now.year, month=now.month, day=now.day, tzinfo=ZONE)
        else:
            moment = datetime.strptime(text.replace("T", " "), "%Y-%m-%d %H:%M").replace(tzinfo=ZONE)
    except ValueError:
        usage()
    return moment.isoformat()


def minutes(duration):
    seconds = int(str(duration).rstrip("s") or 0)
    hours, rest = divmod(round(seconds / 60), 60)
    return f"{hours} h {rest} min" if hours else f"{rest} min"


def distance(metres):
    return f"{metres / 1000:.1f} km" if metres >= 1000 else f"{metres} m"


def transit(step):
    details = step["transitDetails"]
    line = details.get("transitLine", {})
    vehicle = line.get("vehicle", {}).get("name", {}).get("text", "service")
    label = clean(line.get("nameShort") or line.get("name") or "", 60)
    stops = details.get("stopDetails", {})
    board = clean(stops.get("departureStop", {}).get("name", "?"), 80)
    alight = clean(stops.get("arrivalStop", {}).get("name", "?"), 80)
    times = ""
    if stops.get("departureTime") and stops.get("arrivalTime"):
        times = f", {local(stops['departureTime'])} to {local(stops['arrivalTime'])}"
    headsign = f" towards {clean(details['headsign'], 80)}" if details.get("headsign") else ""
    count = details.get("stopCount")
    return f"{clean(vehicle, 30)} {label}{headsign} from {board} to {alight}" + (f", {count} stops" if count else "") + times


def route(args):
    if len(args) not in (3, 5) or args[0] not in MODES:
        usage()
    mode = MODES[args[0]]
    body = {
        "origin": waypoint(args[1]),
        "destination": waypoint(args[2]),
        "travelMode": mode,
        "languageCode": "en-AU",
        "regionCode": "au",
        "units": "METRIC",
    }
    if mode == "DRIVE":
        body["routingPreference"] = "TRAFFIC_UNAWARE"
    if len(args) == 5:
        if args[3] == "depart":
            body["departureTime"] = when(args[4])
        elif args[3] == "arrive" and mode == "TRANSIT":
            body["arrivalTime"] = when(args[4])
        else:
            fail("arrive works for transit alone; use depart for the rest")
    found = post(ROUTES, ROUTE_FIELDS, body, "routes").get("routes", [])
    if not found:
        fail(f"Google Maps found no {args[0]} route between those")
    best = found[0]
    summary = f"{args[0]}: {minutes(best.get('duration', '0s'))}, {distance(best.get('distanceMeters', 0))}"
    if best.get("description"):
        summary += f", via {clean(best['description'], 120)}"
    print(summary)
    for warning in best.get("warnings", []):
        print(f"warning: {clean(warning)}")
    print("steps:")
    for leg in best.get("legs", []):
        for step in leg.get("steps", []):
            if step.get("transitDetails"):
                line = transit(step)
            else:
                line = clean(step.get("navigationInstruction", {}).get("instructions", "continue"), 200)
                if step.get("travelMode") == "WALK" and mode == "TRANSIT":
                    line = f"walk: {line}"
            extra = []
            if step.get("distanceMeters"):
                extra.append(distance(step["distanceMeters"]))
            if step.get("staticDuration") and not step.get("transitDetails"):
                extra.append(minutes(step["staticDuration"]))
            print(f"  {line}" + (f" ({', '.join(extra)})" if extra else ""))


def main(args):
    if not args:
        usage()
    if any(arg.startswith("-") and not LATLNG.match(arg) for arg in args):
        usage()
    match args[0]:
        case "place":
            place(args[1:])
        case "search":
            search(args[1:])
        case "route":
            route(args[1:])
        case _:
            usage()


main(sys.argv[1:])
