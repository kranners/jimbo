import json
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

FORECAST = "https://api.open-meteo.com/v1/forecast"
GEOCODE = "https://geocoding-api.open-meteo.com/v1/search"
ZONE = ZoneInfo("Australia/Melbourne")
TIMEOUT_SECONDS = 20
EX_TEMPFAIL = 75

# A suburb-level point: work is in the same suburb, so a commute's two ends share HOME's forecast.
HOME = {"name": "Collingwood VIC", "latitude": -37.8031, "longitude": 144.9873}
WORK = {"name": "Collingwood VIC"}
RIDE_TIMES = ("08:30", "17:30")

STATES = {
    "vic": "Victoria",
    "nsw": "New South Wales",
    "qld": "Queensland",
    "sa": "South Australia",
    "wa": "Western Australia",
    "tas": "Tasmania",
    "nt": "Northern Territory",
    "act": "Australian Capital Territory",
}

LATLNG = re.compile(r"^(-?\d{1,2}(\.\d+)?),\s*(-?\d{1,3}(\.\d+)?)$")

CODES = {
    0: "clear",
    1: "mostly clear",
    2: "partly cloudy",
    3: "overcast",
    45: "fog",
    48: "freezing fog",
    51: "light drizzle",
    53: "drizzle",
    55: "heavy drizzle",
    56: "freezing drizzle",
    57: "freezing drizzle",
    61: "light rain",
    63: "rain",
    65: "heavy rain",
    66: "freezing rain",
    67: "freezing rain",
    71: "light snow",
    73: "snow",
    75: "heavy snow",
    77: "snow grains",
    80: "light showers",
    81: "showers",
    82: "violent showers",
    85: "snow showers",
    86: "heavy snow showers",
    95: "thunderstorm",
    96: "thunderstorm with hail",
    99: "thunderstorm with hail",
}

HOURLY = [
    "temperature_2m",
    "apparent_temperature",
    "precipitation_probability",
    "precipitation",
    "weather_code",
    "wind_speed_10m",
    "wind_gusts_10m",
    "wind_direction_10m",
]
CURRENT = [
    "temperature_2m",
    "apparent_temperature",
    "relative_humidity_2m",
    "precipitation",
    "weather_code",
    "wind_speed_10m",
    "wind_gusts_10m",
    "wind_direction_10m",
]
DAILY = [
    "weather_code",
    "temperature_2m_max",
    "temperature_2m_min",
    "precipitation_probability_max",
    "precipitation_sum",
    "wind_gusts_10m_max",
    "uv_index_max",
    "sunrise",
    "sunset",
]

USAGE = """usage: weather [now] [<place>]
       weather hourly [<place>]
       weather week [<place>]
       weather ride [today|tomorrow|YYYY-MM-DD] [<there HH:MM> [<back HH:MM>]]
a place is a town or suburb, optionally with its state or country after a comma, or lat,lng;
it defaults to Collingwood, Melbourne; ride defaults to today, there at 08:30 and back at 17:30"""


def usage():
    print(USAGE, file=sys.stderr)
    sys.exit(2)


def fail(message, status=1):
    print(f"weather: {message}", file=sys.stderr)
    sys.exit(status)


def clean(text, limit=120):
    text = re.sub(r"[\x00-\x1f\x7f]+", " ", str(text)).strip()
    return text if len(text) <= limit else text[: limit - 1] + "…"


def get(url, params):
    request = urllib.request.Request(
        url + "?" + urllib.parse.urlencode(params),
        headers={"User-Agent": "butler-weather/1"},
    )
    try:
        with urllib.request.urlopen(request, timeout=TIMEOUT_SECONDS) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        try:
            reason = json.load(error).get("reason", "")
        except ValueError:
            reason = ""
        fail(f"Open-Meteo answered HTTP {error.code}: {clean(reason) or error.reason}")
    except (urllib.error.URLError, TimeoutError) as error:
        fail(f"could not reach Open-Meteo: {error}", EX_TEMPFAIL)


def locate(words):
    """A place from its words, Collingwood when there are none."""
    if not words:
        return HOME
    text = " ".join(words).strip()
    match = LATLNG.match(text)
    if match:
        return {"name": text, "latitude": float(match[1]), "longitude": float(match[3])}
    if text.startswith("-"):
        usage()
    name, _, area = text.partition(",")
    area = area.strip().lower()
    found = get(GEOCODE, {"name": name.strip(), "count": 10, "language": "en", "format": "json"}).get("results", [])
    if area:
        wanted = STATES.get(area, area)
        narrowed = [
            r for r in found
            if wanted.lower() in (r.get("admin1", "").lower(), r.get("country", "").lower(), r.get("country_code", "").lower())
        ]
        found = narrowed or found
    else:
        # A bare name means the Australian one when there is one.
        found = [r for r in found if r.get("country_code") == "AU"] or found
    if not found:
        fail(f"found no place called {clean(text)}")
    best = found[0]
    label = ", ".join(clean(part, 60) for part in (best.get("name"), best.get("admin1"), best.get("country")) if part)
    return {"name": label, "latitude": best["latitude"], "longitude": best["longitude"]}


def forecast(place, days=7):
    return get(
        FORECAST,
        {
            "latitude": place["latitude"],
            "longitude": place["longitude"],
            "current": ",".join(CURRENT),
            "hourly": ",".join(HOURLY),
            "daily": ",".join(DAILY),
            "timezone": "auto",
            "forecast_days": days,
            "wind_speed_unit": "kmh",
        },
    )


def compass(degrees):
    if degrees is None:
        return "?"
    return ["N", "NE", "E", "SE", "S", "SW", "W", "NW"][round(degrees / 45) % 8]


def sky(code):
    return CODES.get(code, f"code {code}")


def number(value, digits=0):
    if value is None:
        return "?"
    return f"{value:.{digits}f}"


def hours(data):
    """The hourly forecast as a list of dicts with a local datetime under `at`."""
    hourly = data["hourly"]
    zone = ZoneInfo(data.get("timezone", "Australia/Melbourne"))
    rows = []
    for index, stamp in enumerate(hourly["time"]):
        row = {key: hourly[key][index] for key in HOURLY}
        row["at"] = datetime.fromisoformat(stamp).replace(tzinfo=zone)
        rows.append(row)
    return rows


def local_now(data):
    return datetime.now(ZoneInfo(data.get("timezone", "Australia/Melbourne")))


def hour_line(row):
    return (
        f"{row['at'].strftime('%a %H:%M')} {number(row['temperature_2m'])}°C (feels {number(row['apparent_temperature'])}) "
        f"{sky(row['weather_code'])}, rain {number(row['precipitation_probability'])}% {number(row['precipitation'], 1)} mm, "
        f"wind {compass(row['wind_direction_10m'])} {number(row['wind_speed_10m'])} gusting {number(row['wind_gusts_10m'])} km/h"
    )


def header(place, data):
    print(f"place: {place['name']} ({place['latitude']:.3f},{place['longitude']:.3f})")
    print(f"now: {local_now(data).strftime('%a %-d %b %Y %H:%M %Z')}")
    print("source: Open-Meteo")


def current(place, data):
    now = data["current"]
    print(
        f"current: {number(now['temperature_2m'])}°C (feels {number(now['apparent_temperature'])}), {sky(now['weather_code'])}, "
        f"humidity {number(now['relative_humidity_2m'])}%, rain {number(now['precipitation'], 1)} mm in the last hour, "
        f"wind {compass(now['wind_direction_10m'])} {number(now['wind_speed_10m'])} gusting {number(now['wind_gusts_10m'])} km/h"
    )
    today = data["daily"]
    print(
        f"today: {number(today['temperature_2m_min'][0])}–{number(today['temperature_2m_max'][0])}°C, {sky(today['weather_code'][0])}, "
        f"rain {number(today['precipitation_probability_max'][0])}% {number(today['precipitation_sum'][0], 1)} mm, "
        f"UV {number(today['uv_index_max'][0])}, sunset {today['sunset'][0][-5:]}"
    )
    upcoming = [row for row in hours(data) if row["at"] > local_now(data)][:24]
    wet = [row for row in upcoming if (row["precipitation_probability"] or 0) >= 40 or (row["precipitation"] or 0) >= 0.2]
    if wet:
        print(f"next rain: from {wet[0]['at'].strftime('%a %H:%M')}, {number(wet[0]['precipitation_probability'])}% {number(wet[0]['precipitation'], 1)} mm")
    else:
        print("next rain: none likely in the next 24 hours")


def hourly(place, data):
    start = local_now(data).replace(minute=0, second=0, microsecond=0)
    print("next 24 hours:")
    for row in [row for row in hours(data) if row["at"] >= start][:24]:
        print(f"  {hour_line(row)}")


def week(place, data):
    daily = data["daily"]
    print("next 7 days:")
    for index, day in enumerate(daily["time"]):
        print(
            f"  {datetime.fromisoformat(day).strftime('%a %-d %b')}: {number(daily['temperature_2m_min'][index])}–"
            f"{number(daily['temperature_2m_max'][index])}°C, {sky(daily['weather_code'][index])}, "
            f"rain {number(daily['precipitation_probability_max'][index])}% {number(daily['precipitation_sum'][index], 1)} mm, "
            f"gusts to {number(daily['wind_gusts_10m_max'][index])} km/h, UV {number(daily['uv_index_max'][index])}"
        )


def judge(rows):
    """Whether to ride through these hours: ("ride" | "ride, with a jacket" | "don't ride", reasons)."""
    chance = max((row["precipitation_probability"] or 0) for row in rows)
    rain = max((row["precipitation"] or 0) for row in rows)
    gust = max((row["wind_gusts_10m"] or 0) for row in rows)
    coldest = min(row["apparent_temperature"] for row in rows if row["apparent_temperature"] is not None)
    hottest = max(row["apparent_temperature"] for row in rows if row["apparent_temperature"] is not None)
    storm = any((row["weather_code"] or 0) >= 95 for row in rows)
    no, maybe = [], []
    if storm:
        no.append("thunderstorms")
    if rain >= 1.0 or (rain >= 0.5 and chance >= 50):
        no.append(f"rain, {chance:.0f}% chance and up to {rain:.1f} mm an hour")
    elif rain >= 0.1 or chance >= 30:
        maybe.append(f"a {chance:.0f}% chance of rain, up to {rain:.1f} mm an hour")
    if gust >= 55:
        no.append(f"gusts to {gust:.0f} km/h")
    elif gust >= 40:
        maybe.append(f"gusty, to {gust:.0f} km/h")
    if hottest >= 38:
        no.append(f"heat, feeling like {hottest:.0f}°C")
    elif hottest >= 32:
        maybe.append(f"hot, feeling like {hottest:.0f}°C")
    if coldest <= 2:
        maybe.append(f"cold, feeling like {coldest:.0f}°C")
    if no:
        return "don't ride, take the Uber", no + maybe
    if maybe:
        return "ride, with a rain jacket" if any("rain" in reason for reason in maybe) else "ride, with care", maybe
    return "ride", ["dry and calm"]


def window(table, at):
    """The hours a trip leaving at `at` crosses, from the hour before to the hour after."""
    return [row for row in table if at - timedelta(hours=1) <= row["at"] <= at + timedelta(hours=1)]


def trip(label, table, at):
    rows = window(table, at)
    if not rows:
        print(f"{label} at {at.strftime('%H:%M')}: outside the forecast")
        return
    verdict, reasons = judge(rows)
    temps = [row["temperature_2m"] for row in rows if row["temperature_2m"] is not None]
    print(f"{label} at {at.strftime('%a %H:%M')}: {verdict} ({'; '.join(reasons)}), {min(temps):.0f}–{max(temps):.0f}°C")
    for row in rows:
        print(f"  {hour_line(row)}")
    if verdict.startswith("don't"):
        # The nearest hour, within two either side, whose own window is fine to ride.
        for shift in (-1, 1, -2, 2):
            moment = at + timedelta(hours=shift)
            near = [row for row in table if moment - timedelta(minutes=30) <= row["at"] <= moment + timedelta(minutes=30)]
            if near and not judge(near)[0].startswith("don't"):
                print(f"  leaving around {moment.strftime('%H:%M')} instead looks rideable ({'; '.join(judge(near)[1])})")
                break


def ride(args):
    today = datetime.now(ZONE).date()
    day = today
    if args and args[0] in ("today", "tomorrow"):
        day = today + timedelta(days=1 if args[0] == "tomorrow" else 0)
        args = args[1:]
    elif args and re.fullmatch(r"\d{4}-\d{2}-\d{2}", args[0]):
        try:
            day = datetime.strptime(args[0], "%Y-%m-%d").date()
        except ValueError:
            usage()
        args = args[1:]
    if len(args) > 2 or not all(re.fullmatch(r"\d{1,2}:\d{2}", arg) for arg in args):
        usage()
    times = list(args) or list(RIDE_TIMES)
    try:
        clocks = [datetime.strptime(text, "%H:%M").time() for text in times]
    except ValueError:
        usage()
    if not 0 <= (day - today).days < 7:
        fail("ride looks up to 6 days ahead")
    data = forecast(HOME)
    table = hours(data)
    print(f"ride: home ({HOME['name']}) to work ({WORK['name']}) and back by e-bike")
    print(f"now: {local_now(data).strftime('%a %-d %b %Y %H:%M %Z')}")
    print("source: Open-Meteo")
    labels = ["there", "back"] if len(times) == 2 else ["trip"]
    for label, clock in zip(labels, clocks):
        trip(label, table, datetime.combine(day, clock, tzinfo=ZONE))


def main(args):
    view = "now"
    if args and args[0] in ("now", "hourly", "week", "ride"):
        view, args = args[0], args[1:]
    if view == "ride":
        ride(args)
        return
    place = locate(args)
    data = forecast(place)
    header(place, data)
    {"now": current, "hourly": hourly, "week": week}[view](place, data)


if __name__ == "__main__":
    main(sys.argv[1:])
