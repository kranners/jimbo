import csv
import io
import os
import re
import sys
import zipfile
from datetime import datetime, timedelta, timezone

import requests

INBOX = "@inbox@"
SELF_IDS = set(filter(None, "@discordSelfIds@".split(",")))
UP_API = "https://api.up.com.au/api/v1"
MAX_BODY = 4000
USAGE = "usage: butler-index-ingest up | butler-index-ingest files"


def fail(message):
    print(f"butler-index-ingest: {message}", file=sys.stderr)
    sys.exit(1)


# Up bank


def up_token():
    try:
        with open(os.path.join(os.environ["CREDENTIALS_DIRECTORY"], "up-token")) as file:
            return file.read().strip()
    except (KeyError, OSError):
        fail("no Up token: write one to /var/lib/secrets/butler-index-up-token")


def up_command(connection):
    session = requests.Session()
    session.headers["Authorization"] = f"Bearer {up_token()}"
    latest = connection.execute("SELECT MAX(ts) FROM records WHERE source = 'up'").fetchone()[0]
    url = f"{UP_API}/transactions"
    params = {"page[size]": "100"}
    if latest:
        params["filter[since]"] = (parse_time(latest) - timedelta(days=14)).isoformat().replace("+00:00", "Z")
    since = params.get("filter[since]")
    seen = set()
    added = 0
    while url:
        response = session.get(url, params=params, timeout=60)
        params = None
        if not response.ok:
            fail(f"Up answered HTTP {response.status_code}")
        page = response.json()
        for transaction in page.get("data", []):
            attributes = transaction["attributes"]
            relationships = transaction.get("relationships", {})
            amount = float(attributes["amount"]["value"])
            category = ((relationships.get("category") or {}).get("data") or {}).get("id")
            parent = ((relationships.get("parentCategory") or {}).get("data") or {}).get("id")
            tags = [tag["id"] for tag in (relationships.get("tags") or {}).get("data") or []]
            transfer = ((relationships.get("transferAccount") or {}).get("data") or {}).get("id")
            # The message and narrative on money coming in were written by whoever sent it, so only Aaron's own, on money going out, are kept.
            message = attributes.get("message") if amount < 0 else None
            raw = attributes.get("rawText") if amount < 0 else None
            seen.add(transaction["id"])
            upsert(
                connection,
                "up",
                transaction["id"],
                "transfer" if transfer else "payment",
                parse_time(attributes["createdAt"]),
                title=attributes.get("description") or "",
                body=" ".join(filter(None, [raw, message, category, parent, *tags])),
                amount=amount,
                currency=attributes["amount"]["currencyCode"],
                extra={
                    "status": attributes.get("status"),
                    "category": category,
                    "parentCategory": parent,
                    "tags": tags,
                    "message": message,
                },
            )
            added += 1
        connection.commit()
        url = (page.get("links") or {}).get("next")
    if since:
        # A hold Up dropped instead of settling is gone from the API, so it goes from the index too.
        for (uid,) in connection.execute(
            "SELECT uid FROM records WHERE source = 'up' AND ts >= ? AND json_extract(extra, '$.status') = 'HELD'", (since.replace("Z", "+00:00"),)
        ).fetchall():
            if uid not in seen:
                connection.execute("DELETE FROM records WHERE source = 'up' AND uid = ?", (uid,))
        connection.commit()
    record_ingest(connection, "up", added)
    print(f"up: {added} transactions")


# Export files in the inbox, extracted or zipped


def export_files(directory):
    for root, _, names in os.walk(directory):
        for name in sorted(names):
            path = os.path.join(root, name)
            if name.lower().endswith(".zip"):
                try:
                    archive = zipfile.ZipFile(path)
                except zipfile.BadZipFile:
                    print(f"skipping {path}: not a zip", file=sys.stderr)
                    continue
                for member in archive.namelist():
                    if not member.endswith("/"):
                        yield member, (lambda archive=archive, member=member: archive.read(member))
            else:
                yield os.path.relpath(path, directory), (lambda path=path: open(path, "rb").read())


def load_json(read):
    try:
        return json.loads(read().decode("utf-8-sig"))
    except (ValueError, UnicodeDecodeError):
        return None


# Discord data package: messages/index.json names each channel, messages/c<id>/messages.json (or .csv) holds Aaron's own messages.


def discord_command(connection):
    files = dict(export_files(os.path.join(INBOX, "discord")))
    labels = {}
    for name, read in files.items():
        if name.lower().endswith("messages/index.json"):
            labels.update(load_json(read) or {})
    added = 0
    for name, read in files.items():
        match = re.search(r"(?:^|/)c?(\d{5,})/messages\.(json|csv)$", name, re.IGNORECASE)
        if not match:
            continue
        channel = match.group(1)
        if match.group(2).lower() == "json":
            messages = load_json(read) or []
        else:
            messages = list(csv.DictReader(io.StringIO(read().decode("utf-8-sig"))))
        meta = load_json(files[name.rsplit("/", 1)[0] + "/channel.json"]) if name.rsplit("/", 1)[0] + "/channel.json" in files else {}
        meta = meta or {}
        guild = (meta.get("guild") or {}).get("name")
        label = labels.get(channel) or " in ".join(filter(None, [meta.get("name"), guild])) or f"channel {channel}"
        for message in messages if isinstance(messages, list) else []:
            if not isinstance(message, dict):
                continue
            # The data package holds only Aaron's own messages; anything with an author not his is dropped, never stored.
            authors = [message[key] for key in ("author", "Author", "AuthorID", "author_id", "authorId", "user", "sender") if key in message]
            if authors:
                author = authors[0]
                author_id = str(author.get("id") or "") if isinstance(author, dict) else str(author or "")
                if not author_id or author_id not in SELF_IDS:
                    continue
            identifier = str(message.get("ID") or message.get("id") or "")
            stamp = message.get("Timestamp") or message.get("timestamp")
            if not identifier or not stamp:
                continue
            try:
                moment = parse_time(stamp.replace(" ", "T"))
            except ValueError:
                continue
            contents = (message.get("Contents") or message.get("content") or "")[:MAX_BODY]
            attachments = message.get("Attachments") or message.get("attachments") or ""
            upsert(
                connection,
                "discord",
                identifier,
                "message",
                moment,
                title=label,
                body=contents,
                extra={"channel": channel, "attachments": len(attachments.split()) if isinstance(attachments, str) else len(attachments)},
            )
            added += 1
        connection.commit()
    record_ingest(connection, "discord", added)
    print(f"discord: {added} of Aaron's messages")


# Google Maps location history: Takeout's Semantic Location History, and the newer on-device Timeline exports from Android and iOS.


def degrees(text):
    if isinstance(text, dict):
        text = text.get("latLng") or ""
    numbers = re.findall(r"-?\d+(?:\.\d+)?", str(text).replace("geo:", ""))
    return (round(float(numbers[0]), 5), round(float(numbers[1]), 5)) if len(numbers) >= 2 else (None, None)


def e7(location):
    if not location or "latitudeE7" not in location:
        return None, None
    return round(location["latitudeE7"] / 1e7, 5), round(location["longitudeE7"] / 1e7, 5)


def takeout_start(duration):
    duration = duration or {}
    if duration.get("startTimestamp"):
        return duration["startTimestamp"], parse_time(duration["startTimestamp"])
    if str(duration.get("startTimestampMs", "")).isdigit():
        return duration["startTimestampMs"], datetime.fromtimestamp(int(duration["startTimestampMs"]) / 1000, timezone.utc)
    return None, None


def location_takeout(connection, objects):
    added = 0
    for item in objects:
        if "placeVisit" in item:
            visit = item["placeVisit"]
            location = visit.get("location") or {}
            start, moment = takeout_start(visit.get("duration"))
            if not start:
                continue
            latitude, longitude = e7(location)
            upsert(
                connection,
                "location",
                f"visit-{start}-{location.get('placeId', '')}",
                "visit",
                moment,
                title=location.get("name") or location.get("semanticType") or "a place",
                place=location.get("address") or "",
                latitude=latitude,
                longitude=longitude,
                extra={"until": (visit.get("duration") or {}).get("endTimestamp") or (visit.get("duration") or {}).get("endTimestampMs")},
            )
            added += 1
        elif "activitySegment" in item:
            segment = item["activitySegment"]
            start, moment = takeout_start(segment.get("duration"))
            if not start:
                continue
            latitude, longitude = e7(segment.get("startLocation"))
            upsert(
                connection,
                "location",
                f"activity-{start}",
                "activity",
                moment,
                title=(segment.get("activityType") or "moving").lower().replace("_", " "),
                latitude=latitude,
                longitude=longitude,
                extra={"until": (segment.get("duration") or {}).get("endTimestamp"), "metres": segment.get("distance")},
            )
            added += 1
    return added


def location_segments(connection, segments):
    added = 0
    for segment in segments:
        start = segment.get("startTime")
        if not start or not isinstance(segment, dict):
            continue
        if "visit" in segment:
            candidate = segment["visit"].get("topCandidate") or {}
            latitude, longitude = degrees(candidate.get("placeLocation"))
            upsert(
                connection,
                "location",
                f"visit-{start}",
                "visit",
                parse_time(start),
                title=(candidate.get("semanticType") or "a place").lower().replace("_", " "),
                place=f"{latitude}, {longitude}" if latitude is not None else "",
                latitude=latitude,
                longitude=longitude,
                extra={"until": segment.get("endTime"), "placeId": candidate.get("placeId") or candidate.get("placeID")},
            )
            added += 1
        elif "activity" in segment:
            activity = segment["activity"]
            latitude, longitude = degrees(activity.get("start"))
            kind = ((activity.get("topCandidate") or {}).get("type") or "moving").lower().replace("_", " ")
            upsert(
                connection,
                "location",
                f"activity-{start}",
                "activity",
                parse_time(start),
                title=kind,
                latitude=latitude,
                longitude=longitude,
                extra={"until": segment.get("endTime"), "metres": activity.get("distanceMeters")},
            )
            added += 1
    return added


def location_command(connection):
    added = 0
    for name, read in export_files(os.path.join(INBOX, "location")):
        if not name.lower().endswith(".json"):
            continue
        data = load_json(read)
        if isinstance(data, dict) and "timelineObjects" in data:
            added += location_takeout(connection, data["timelineObjects"])
        elif isinstance(data, dict) and "semanticSegments" in data:
            added += location_segments(connection, data["semanticSegments"])
        elif isinstance(data, list):
            added += location_segments(connection, [item for item in data if isinstance(item, dict)])
        else:
            print(f"skipping {name}: not a location history format this knows", file=sys.stderr)
        connection.commit()
    record_ingest(connection, "location", added)
    print(f"location: {added} visits and trips")


def main():
    if sys.argv[1:] == ["up"]:
        up_command(open_for_writing())
    elif sys.argv[1:] == ["files"]:
        connection = open_for_writing()
        discord_command(connection)
        location_command(connection)
    else:
        print(USAGE, file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main()
