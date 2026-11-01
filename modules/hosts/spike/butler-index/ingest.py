import csv
import hashlib
import io
import os
import re
import sys
import time
import zipfile
from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo

import requests

INBOX = "@inbox@"
LOCAL = ZoneInfo("Australia/Melbourne")
UP_API = "https://api.up.com.au/api/v1"
MAX_BODY = 4000
USAGE = "usage: butler-index-ingest up | butler-index-ingest slack | butler-index-ingest files"


def fail(message):
    print(f"butler-index-ingest: {message}", file=sys.stderr)
    sys.exit(1)


# Up bank


def credential(name, path):
    try:
        with open(os.path.join(os.environ["CREDENTIALS_DIRECTORY"], name)) as file:
            return file.read().strip()
    except (KeyError, OSError):
        fail(f"no {name}: write one to {path}")


def digest(*parts):
    return hashlib.sha256("\x1f".join(str(part) for part in parts).encode()).hexdigest()[:24]


def up_command(connection):
    session = requests.Session()
    session.headers["Authorization"] = f"Bearer {credential('up-token', '/var/lib/secrets/butler-index-up-token')}"
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


# Discord data package: messages/index.json names each channel, messages/c<id>/messages.json (or .csv) holds its messages; the package itself holds only Aaron's side.


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
            authors = [message[key] for key in ("author", "Author", "user", "sender") if key in message]
            author = authors[0] if authors else None
            author = (author.get("global_name") or author.get("name") or author.get("username")) if isinstance(author, dict) else author
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
                body=f"{author}: {contents}" if author else contents,
                extra={"channel": channel, "author": author, "attachments": len(attachments.split()) if isinstance(attachments, str) else len(attachments)},
            )
            added += 1
        connection.commit()
    record_ingest(connection, "discord", added)
    print(f"discord: {added} messages")


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


# Messenger and Instagram chats, both sides: Messenger's encrypted secure-storage download (one JSON per chat with senderName and timestamp)
# and Meta's "Download your information" exports (messages/inbox/<chat>/message_N.json with sender_name and timestamp_ms).


def unmangle(text):
    # Meta's information exports write UTF-8 text as if each byte were a Latin-1 character.
    try:
        return text.encode("latin-1").decode("utf-8")
    except (UnicodeEncodeError, UnicodeDecodeError):
        return text


def chat_messages(data):
    if not isinstance(data, dict) or not isinstance(data.get("messages"), list):
        return None
    mangled = "timestamp_ms" in (data["messages"][0] if data["messages"] else {})
    fix = unmangle if mangled else (lambda text: text)
    names = [fix(person.get("name", "")) if isinstance(person, dict) else fix(str(person)) for person in data.get("participants") or []]
    thread = fix(data.get("threadName") or data.get("title") or "") or ", ".join(filter(None, names)) or "a chat"
    for message in data["messages"]:
        if not isinstance(message, dict) or message.get("isUnsent"):
            continue
        stamp = message.get("timestamp_ms") or message.get("timestamp")
        sender = fix(message.get("sender_name") or message.get("senderName") or "")
        text = fix(message.get("content") or message.get("text") or "")
        media = len(message.get("media") or message.get("photos") or []) + len(message.get("videos") or []) + len(message.get("audio_files") or [])
        if not isinstance(stamp, int) or not (text or media):
            continue
        yield thread, sender, datetime.fromtimestamp(stamp / 1000, timezone.utc), text, media


def chats_command(connection, source, directories):
    added = 0
    for directory in directories:
        for name, read in export_files(os.path.join(INBOX, directory)):
            if not name.lower().endswith(".json"):
                continue
            for thread, sender, moment, text, media in chat_messages(load_json(read)) or []:
                upsert(
                    connection,
                    source,
                    digest(thread, sender, moment.isoformat(), text[:200]),
                    "message",
                    moment,
                    title=thread,
                    body=f"{sender}: {text[:MAX_BODY]}" if sender else text[:MAX_BODY],
                    extra={"sender": sender, "media": media} if media else {"sender": sender},
                )
                added += 1
            connection.commit()
    record_ingest(connection, source, added)
    print(f"{source}: {added} messages")


# Hevy's workouts CSV has one row per set; each workout becomes one record listing its exercises and sets.


def hevy_command(connection):
    workouts = {}
    for name, read in export_files(os.path.join(INBOX, "hevy")):
        if not name.lower().endswith(".csv"):
            continue
        for row in csv.DictReader(io.StringIO(read().decode("utf-8-sig"))):
            key = (row.get("title") or "", row.get("start_time") or "")
            workouts.setdefault(key, {"end": row.get("end_time"), "description": row.get("description") or "", "exercises": {}})
            sets = workouts[key]["exercises"].setdefault(row.get("exercise_title") or "exercise", [])
            weight, reps = row.get("weight_kg"), row.get("reps")
            sets.append(" ".join(filter(None, [f"{float(weight):g} kg" if weight else "", f"x{reps}" if reps else "", row.get("duration_seconds") and f"{row['duration_seconds']} s", row.get("set_type") if row.get("set_type") not in (None, "", "normal") else ""])))
    added = 0
    for (title, start), workout in workouts.items():
        try:
            moment = datetime.strptime(start, "%b %d, %Y, %I:%M %p").replace(tzinfo=LOCAL)
        except ValueError:
            continue
        summary = "; ".join(f"{exercise}: {', '.join(sets)}" for exercise, sets in workout["exercises"].items())
        upsert(
            connection,
            "hevy",
            digest(title, start),
            "workout",
            moment,
            title=title,
            body=" ".join(filter(None, [workout["description"], summary]))[:MAX_BODY],
            extra={"until": workout["end"], "exercises": len(workout["exercises"]), "sets": sum(len(sets) for sets in workout["exercises"].values())},
        )
        added += 1
    connection.commit()
    record_ingest(connection, "hevy", added)
    print(f"hevy: {added} workouts")


# PayPal's Activity download CSVs, one per year; rows without a counterparty are PayPal's own funding and conversion steps.


def paypal_command(connection):
    added = 0
    for name, read in export_files(os.path.join(INBOX, "paypal")):
        if not name.lower().endswith(".csv"):
            continue
        for row in csv.DictReader(io.StringIO(read().decode("utf-8-sig"))):
            # An authorisation is a hold that the payment it precedes repeats, so only the payment is kept.
            if not row.get("Name") or not row.get("Transaction ID") or "Authorisation" in (row.get("Type") or ""):
                continue
            try:
                moment = datetime.strptime(f"{row['Date']} {row['Time']}", "%d/%m/%Y %H:%M:%S").replace(tzinfo=LOCAL)
                amount = float(row["Amount"].replace(",", ""))
            except (KeyError, ValueError):
                continue
            upsert(
                connection,
                "paypal",
                f"{row['Transaction ID']}:{row.get('Type')}",
                "payment",
                moment,
                title=row["Name"],
                body=" ".join(filter(None, [row.get("Item Title"), row.get("Type"), row.get("Status")])),
                amount=amount,
                currency=row.get("Currency"),
                extra={"type": row.get("Type"), "status": row.get("Status")},
            )
            added += 1
        connection.commit()
    record_ingest(connection, "paypal", added)
    print(f"paypal: {added} payments")


# Steam's purchase history page saved as text: each purchase starts with a line like "28 Sep, 2026", then its items, type and
# payment method, then a tab-separated line of price, tax, shipping, total, wallet change and balance.

STEAM_DATE = re.compile(r"^(\d{1,2} \w{3}, \d{4})\t?(.*)$")
STEAM_TYPE = re.compile(r"Purchase|Refund|Market|Gift|Conversion|Transaction")


def steam_money(cell):
    match = re.search(r"(-?)(A?\$)\s?([\d,]+\.\d{2})(?:\s+([A-Z]{3}))?", cell or "")
    if not match:
        return None, None
    currency = match.group(4) or ("AUD" if match.group(2) == "A$" else "USD")
    return float(match.group(3).replace(",", "")), currency


def steam_command(connection):
    added = 0
    for name, read in export_files(os.path.join(INBOX, "steam")):
        if not name.lower().startswith("purchases"):
            continue
        blocks, current = [], None
        for line in read().decode("utf-8", "replace").splitlines():
            match = STEAM_DATE.match(line.lstrip("\t"))
            if match:
                current = {"date": match.group(1), "lines": [match.group(2).strip("\t")]}
                blocks.append(current)
            elif current is not None:
                current["lines"].append(line)
        for block in blocks:
            texts = [line.strip() for line in block["lines"] if line.strip() and "\t" not in line and not re.search(r"\$\s?[\d.]+|%$", line)]
            kind = next((text for text in texts if STEAM_TYPE.search(text)), "Purchase")
            items = texts[: texts.index(kind)] if kind in texts else texts[:1]
            money = [line for line in block["lines"] if "\t" in line and "$" in line]
            cells = money[-1].split("\t") if money else []
            amount, currency = steam_money(cells[len(cells) - 3]) if len(cells) >= 3 else (None, None)
            if amount is not None and "Refund" not in kind:
                amount = -amount
            elif amount is None and len(cells) >= 2:
                # A Community Market sale or purchase has no total, only the signed change to the Steam Wallet.
                change = cells[len(cells) - 2].strip()
                amount, currency = steam_money(change)
                if amount is not None and change.startswith("-"):
                    amount = -amount
            upsert(
                connection,
                "steam",
                digest(block["date"], *block["lines"]),
                "payment",
                datetime.strptime(block["date"], "%d %b, %Y").replace(hour=12, tzinfo=LOCAL),
                title=", ".join(items) or kind,
                body=kind,
                amount=amount,
                currency=currency,
                extra={"type": kind},
            )
            added += 1
        connection.commit()
    record_ingest(connection, "steam", added)
    print(f"steam: {added} purchases")


# Slack, both sides of every conversation Aaron's user token can read, incrementally: each channel keeps the newest ts it has
# ingested in the state table, and each run re-reads the week before it so replies to recent threads are picked up.

SLACK_API = "https://slack.com/api"
SLACK_OVERLAP = 7 * 24 * 3600
SLACK_PAUSE = 1.3


def slack_call(session, method, **params):
    while True:
        response = session.get(f"{SLACK_API}/{method}", params=params, timeout=60)
        if response.status_code == 429:
            time.sleep(int(response.headers.get("Retry-After", "30")) + 1)
            continue
        time.sleep(SLACK_PAUSE)
        data = response.json() if response.ok else {"ok": False, "error": f"HTTP {response.status_code}"}
        if not data.get("ok"):
            raise RuntimeError(f"{method}: {data.get('error')}")
        return data


def slack_pages(session, method, key, **params):
    cursor = None
    while True:
        data = slack_call(session, method, limit=200, **params, **({"cursor": cursor} if cursor else {}))
        yield from data.get(key) or []
        cursor = (data.get("response_metadata") or {}).get("next_cursor")
        if not cursor:
            return


def slack_text(message, users):
    text = re.sub(r"<@(\w+)>", lambda match: "@" + users.get(match.group(1), match.group(1)), message.get("text") or "")
    files = ", ".join(file.get("name") or file.get("title") or "a file" for file in message.get("files") or [])
    return " ".join(filter(None, [text, files and f"[{files}]"]))[:MAX_BODY]


def slack_command(connection):
    session = requests.Session()
    session.headers["Authorization"] = f"Bearer {credential('slack-token', '/var/lib/secrets/butler-index-slack-token')}"
    users = {user["id"]: user.get("real_name") or (user.get("profile") or {}).get("real_name") or user.get("name") for user in slack_pages(session, "users.list", "members")}
    added = 0
    for channel in slack_pages(session, "conversations.list", "channels", types="public_channel,private_channel,mpim,im", exclude_archived="false"):
        if channel.get("is_im"):
            label = f"DM with {users.get(channel.get('user'), channel.get('user'))}"
        elif channel.get("is_mpim"):
            label = "group DM " + ((channel.get("purpose") or {}).get("value") or channel.get("name", ""))
        else:
            label = f"#{channel.get('name')}"
        key = f"slack:{channel['id']}"
        row = connection.execute("SELECT value FROM state WHERE key = ?", (key,)).fetchone()
        oldest = max(float(row[0]) - SLACK_OVERLAP, 0) if row else 0
        newest = float(row[0]) if row else 0
        try:
            since = {"oldest": f"{oldest:.6f}"} if oldest else {}
            for message in slack_pages(session, "conversations.history", "messages", channel=channel["id"], **since):
                thread = [message]
                if message.get("reply_count"):
                    thread = list(slack_pages(session, "conversations.replies", "messages", channel=channel["id"], ts=message["ts"]))
                for reply in thread:
                    if reply.get("subtype") in ("channel_join", "channel_leave"):
                        continue
                    author = users.get(reply.get("user"), reply.get("username") or reply.get("user") or "")
                    upsert(
                        connection,
                        "slack",
                        f"{channel['id']}:{reply['ts']}",
                        "message",
                        datetime.fromtimestamp(float(reply["ts"]), timezone.utc),
                        title=label,
                        body=f"{author}: {slack_text(reply, users)}",
                        extra={"channel": channel["id"], "author": author, "thread": reply.get("thread_ts")},
                    )
                    newest = max(newest, float(reply["ts"]))
                    added += 1
                connection.commit()
        except RuntimeError as error:
            print(f"slack: skipping {label}: {error}", file=sys.stderr)
            continue
        connection.execute("INSERT INTO state (key, value) VALUES (?, ?) ON CONFLICT (key) DO UPDATE SET value = excluded.value", (key, f"{newest:.6f}"))
        connection.commit()
    record_ingest(connection, "slack", added)
    print(f"slack: {added} messages")


def main():
    if sys.argv[1:] == ["up"]:
        up_command(open_for_writing())
    elif sys.argv[1:] == ["slack"]:
        slack_command(open_for_writing())
    elif sys.argv[1:] == ["files"]:
        connection = open_for_writing()
        discord_command(connection)
        location_command(connection)
        chats_command(connection, "messenger", ["messenger-e2ee", "facebook"])
        chats_command(connection, "instagram", ["instagram"])
        hevy_command(connection)
        paypal_command(connection)
        steam_command(connection)
    else:
        print(USAGE, file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main()
