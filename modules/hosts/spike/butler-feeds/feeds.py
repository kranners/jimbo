"""butler-feeds: live routes into butler's personal data index, written in the shapes its existing readers already take.

Each feed fetches from a live source, read-only, keeps what it has seen in its own state, and writes one file into the
index inbox, replaced whole and only when it changed, so the index's ingest picks it up like a fresh export:

  letterboxd  Letterboxd's public diary RSS            -> inbox/exports/live-letterboxd.zip (diary, ratings, reviews)
  goodreads   Goodreads' public shelf RSS              -> inbox/exports/live-goodreads.csv (the library export's columns)
  spotify     Spotify's recently played, OAuth         -> inbox/spotify/Streaming_History_Audio_live.json
  steam       Steam's Web API library and playtime     -> inbox/exports/live-steam-library.csv
  paypal      PayPal's transaction search, an app      -> inbox/paypal/live-paypal.csv (the activity CSV's columns)
  mail        statements and receipts in Aaron's mail  -> inbox/exports/live-hostplus-*.pdf, live-cmc-*,
                                                          inbox/uber/live-*-0.csv, inbox/amazon/live-Order History.csv

A feed with no login or user yet is skipped and says what it needs in status.json; nothing here posts, pays or changes
anything at any source.
"""

import base64
import csv
import email
import email.policy
import getpass
import hashlib
import html
import io
import json
import os
import re
import secrets
import sqlite3
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ElementTree
import zipfile
from datetime import datetime, timedelta, timezone
from email.utils import parsedate_to_datetime
from zoneinfo import ZoneInfo

CONFIG = json.loads(os.environ.get("BUTLER_FEEDS_CONFIG_JSON") or open(os.environ["BUTLER_FEEDS_CONFIG"]).read())
STATE = CONFIG["stateDir"]
INBOX = CONFIG["inbox"]
INDEX = CONFIG["indexDb"]
LOCAL = ZoneInfo(CONFIG.get("timeZone") or "Australia/Melbourne")
AGENT = "butler-feeds/1 (personal data, read-only)"
FEEDS = ("letterboxd", "goodreads", "spotify", "steam", "paypal", "mail")
SPOTIFY_REDIRECT = "http://127.0.0.1:8888/callback"
SPOTIFY_SCOPE = "user-read-recently-played"
MAIL_LOOKBACK_DAYS = 730
SEEN_CAP = 20000


def now():
    return datetime.now(timezone.utc)


def path(*parts):
    return os.path.join(STATE, *parts)


def load(name, default):
    try:
        with open(name) as handle:
            return json.load(handle)
    except (OSError, ValueError):
        return default


def save(name, data, mode=0o600):
    os.makedirs(os.path.dirname(name), exist_ok=True)
    temporary = f"{name}.{os.getpid()}.tmp"
    with open(os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, mode), "w") as handle:
        json.dump(data, handle, ensure_ascii=False, indent=1, sort_keys=True)
    os.replace(temporary, name)


def secret(feed):
    return load(path("secrets", f"{feed}.json"), None)


def settings():
    return load(path("config.json"), {})


class Skip(Exception):
    """The feed cannot run yet, for a reason that is not a failure: no login, no user."""


def deliver(folder, name, data):
    """Writes data into inbox/<folder>/<name> through a partial in the inbox's root, only when it changed."""
    target = os.path.join(INBOX, folder, name)
    if not os.path.isdir(os.path.dirname(target)):
        raise RuntimeError(f"the index inbox has no folder {folder}")
    try:
        with open(target, "rb") as handle:
            if handle.read() == data:
                return False
    except OSError:
        pass
    partial = os.path.join(INBOX, f".feeds-{folder}-{name}.partial")
    with open(os.open(partial, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600), "wb") as handle:
        handle.write(data)
    os.replace(partial, target)
    return True


def others(folder, mine):
    """Every file in an inbox folder but this feed's own, for the overlap with an export to be left out."""
    directory = os.path.join(INBOX, folder)
    for root, folders, names in os.walk(directory):
        folders[:] = [folder for folder in folders if not folder.startswith(".")]
        for name in sorted(names):
            if not name.startswith(".") and not name.startswith("live-") and name != mine:
                yield os.path.join(root, name)


def members(file_path):
    """A file's contents, or each CSV member's when it is a zip, as (name, bytes)."""
    if file_path.lower().endswith(".zip"):
        try:
            with zipfile.ZipFile(file_path) as archive:
                for info in archive.infolist():
                    if not info.is_dir() and info.filename.lower().endswith(".csv") and info.file_size < 64 * 1024 * 1024:
                        yield info.filename, archive.read(info)
        except (OSError, zipfile.BadZipFile):
            return
    elif file_path.lower().endswith(".csv"):
        with open(file_path, "rb") as handle:
            yield file_path, handle.read()


def csv_rows(data):
    try:
        return list(csv.DictReader(io.StringIO(data.decode("utf-8-sig"))))
    except (UnicodeDecodeError, csv.Error):
        return []


def csv_bytes(header, rows):
    out = io.StringIO()
    writer = csv.DictWriter(out, fieldnames=header, lineterminator="\n", extrasaction="ignore")
    writer.writeheader()
    for row in rows:
        writer.writerow(row)
    return out.getvalue().encode()


def zip_bytes(files):
    out = io.BytesIO()
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as archive:
        for name, data in files.items():
            info = zipfile.ZipInfo(name, date_time=(2020, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(info, data)
    return out.getvalue()


def request(url, data=None, headers=None, method=None, timeout=60):
    headers = {"User-Agent": AGENT, **(headers or {})}
    attempt = 0
    while True:
        try:
            with urllib.request.urlopen(urllib.request.Request(url, data=data, headers=headers, method=method), timeout=timeout) as response:
                return response.read()
        except urllib.error.HTTPError as error:
            if error.code in (429, 500, 502, 503, 504) and attempt < 2:
                attempt += 1
                time.sleep(min(int(error.headers.get("Retry-After") or 5 * attempt), 30))
                continue
            raise


def get_json(url, headers=None):
    return json.loads(request(url, headers=headers))


def text_of(markup):
    markup = re.sub(r"(?is)<(script|style|head).*?</\1>", " ", markup or "")
    markup = re.sub(r"(?i)<br\s*/?>|</(p|div|tr|li|h\d|table)>", "\n", markup)
    text = html.unescape(re.sub(r"<[^>]+>", " ", markup))
    lines = [re.sub(r"[ \t ​‌͏]+", " ", line).strip() for line in text.splitlines()]
    return "\n".join(line for line in lines if line)


def index_rows(query, *params):
    """Reads Aaron's index read-only, for a user id his own browser history names; empty when there is no index."""
    if not os.path.exists(INDEX):
        return []
    try:
        connection = sqlite3.connect(f"file:{INDEX}?mode=ro", uri=True, timeout=30)
        try:
            return connection.execute(query, params).fetchall()
        finally:
            connection.close()
    except sqlite3.Error:
        return []


def most_common(pattern, like):
    counts = {}
    for (body,) in index_rows("SELECT body FROM records WHERE source = 'browser' AND body LIKE ? LIMIT 20000", like):
        match = re.search(pattern, body or "")
        if match:
            counts[match.group(1)] = counts.get(match.group(1), 0) + 1
    return max(counts, key=counts.get) if counts else None


# Letterboxd: https://letterboxd.com/<user>/rss/ holds the newest 50 diary entries and lists; each run adds what is new.

LETTERBOXD_NS = {"letterboxd": "https://letterboxd.com"}
DIARY = ["Date", "Name", "Year", "Letterboxd URI", "Rating", "Rewatch", "Tags", "Watched Date"]
RATINGS = ["Date", "Name", "Year", "Letterboxd URI", "Rating"]
REVIEWS = ["Date", "Name", "Year", "Letterboxd URI", "Rating", "Rewatch", "Review", "Tags", "Watched Date"]


def letterboxd_user():
    user = settings().get("letterboxd")
    if user:
        return user, "set"
    for file_path in others("exports", "live-letterboxd.zip"):
        if not file_path.lower().endswith(".zip"):
            continue
        for name, data in members(file_path):
            if name.rsplit("/", 1)[-1].lower() == "profile.csv":
                for row in csv_rows(data)[:1]:
                    if row.get("Username"):
                        return row["Username"].strip(), "from the Letterboxd export's profile"
    raise Skip("needs the Letterboxd username: no Letterboxd export with a profile in the inbox; run sudo butler-feeds-login letterboxd <username>")


def letterboxd_review(description):
    text = text_of(description)
    lines = [line for line in text.splitlines() if not re.match(r"(?i)^(watched|rewatched) on ", line) and line.lower() != "this review may contain spoilers."]
    return "\n".join(lines).strip()


def parse_letterboxd(feed):
    entries = {}
    root = ElementTree.fromstring(feed)
    for item in root.iter("item"):
        title = item.findtext("letterboxd:filmTitle", namespaces=LETTERBOXD_NS)
        watched = item.findtext("letterboxd:watchedDate", namespaces=LETTERBOXD_NS)
        link = (item.findtext("link") or "").strip()
        if not title or not watched or not link:
            continue
        published = item.findtext("pubDate")
        try:
            logged = parsedate_to_datetime(published).astimezone(LOCAL).date().isoformat() if published else watched
        except (TypeError, ValueError):
            logged = watched
        rating = item.findtext("letterboxd:memberRating", namespaces=LETTERBOXD_NS) or ""
        entries[link] = {
            "Date": logged,
            "Name": title.strip(),
            "Year": (item.findtext("letterboxd:filmYear", namespaces=LETTERBOXD_NS) or "").strip(),
            "Letterboxd URI": link,
            "Rating": rating.strip(),
            "Rewatch": "Yes" if (item.findtext("letterboxd:rewatch", namespaces=LETTERBOXD_NS) or "").strip().lower() == "yes" else "",
            "Tags": "",
            "Watched Date": watched.strip(),
            "Review": letterboxd_review(item.findtext("description") or ""),
        }
    return entries


def letterboxd():
    user, how = letterboxd_user()
    state_file = path("state", "letterboxd.json")
    state = load(state_file, {"entries": {}})
    state["entries"].update(parse_letterboxd(request(f"https://letterboxd.com/{urllib.parse.quote(user)}/rss/")))
    save(state_file, state)
    exported = set()
    for file_path in others("exports", "live-letterboxd.zip"):
        for name, data in members(file_path):
            if name.rsplit("/", 1)[-1].lower() == "diary.csv":
                exported |= {(row.get("Name", "").strip(), row.get("Year", "").strip(), row.get("Watched Date", "").strip()) for row in csv_rows(data)}
    entries = sorted(
        (entry for entry in state["entries"].values() if (entry["Name"], entry["Year"], entry["Watched Date"]) not in exported),
        key=lambda entry: (entry["Watched Date"], entry["Letterboxd URI"]),
    )
    files = {
        "diary.csv": csv_bytes(DIARY, entries),
        "ratings.csv": csv_bytes(RATINGS, [entry for entry in entries if entry["Rating"]]),
        "reviews.csv": csv_bytes(REVIEWS, [entry for entry in entries if entry["Review"]]),
    }
    changed = deliver("exports", "live-letterboxd.zip", zip_bytes(files))
    return f"{len(entries)} diary entries newer than the export, for {user} ({how})", changed


# Goodreads: https://www.goodreads.com/review/list_rss/<user id>?shelf=<shelf> pages through a public shelf.

GOODREADS = ["Book Id", "Title", "Author", "My Rating", "Average Rating", "Number of Pages", "Original Publication Year", "Date Read", "Date Added", "Bookshelves", "Exclusive Shelf", "My Review", "ISBN13", "Read Count"]
GOODREADS_SHELVES = ("read", "currently-reading", "to-read")


def goodreads_user():
    user = settings().get("goodreads")
    if user:
        return str(user), "set"
    user = most_common(r"goodreads\.com/(?:review/list|user/show)/(\d+)", "%goodreads.com/%")
    if user:
        return user, "from Aaron's browser history"
    raise Skip("needs the Goodreads user id, the number in the profile's address: run sudo butler-feeds-login goodreads <id>")


def goodreads_date(text):
    try:
        return parsedate_to_datetime(text).astimezone(LOCAL).strftime("%Y/%m/%d") if text and text.strip() else ""
    except (TypeError, ValueError):
        return ""


def parse_goodreads(feed, shelf):
    books = []
    root = ElementTree.fromstring(feed)
    for item in root.iter("item"):
        book_id = (item.findtext("book_id") or "").strip()
        title = (item.findtext("title") or "").strip()
        if not book_id or not title:
            continue
        isbn = re.sub(r"\D", "", item.findtext("isbn") or "")
        shelves = [name.strip() for name in (item.findtext("user_shelves") or "").split(",") if name.strip() and name.strip() not in GOODREADS_SHELVES]
        books.append(
            {
                "Book Id": book_id,
                "Title": title,
                "Author": (item.findtext("author_name") or "").strip(),
                "My Rating": (item.findtext("user_rating") or "0").strip(),
                "Average Rating": (item.findtext("average_rating") or "").strip(),
                "Number of Pages": (item.findtext("book/num_pages") or "").strip(),
                "Original Publication Year": (item.findtext("book_published") or "").strip(),
                "Date Read": goodreads_date(item.findtext("user_read_at")),
                "Date Added": goodreads_date(item.findtext("user_date_added")),
                "Bookshelves": ", ".join(shelves),
                "Exclusive Shelf": shelf,
                "My Review": text_of(item.findtext("user_review") or ""),
                "ISBN13": isbn if len(isbn) == 13 else "",
                "Read Count": "1" if shelf == "read" else "0",
            }
        )
    return books


def goodreads():
    user, how = goodreads_user()
    state_file = path("state", "goodreads.json")
    state = load(state_file, {"books": {}})
    fetched = {}
    for shelf in GOODREADS_SHELVES:
        for page in range(1, 21):
            books = parse_goodreads(request(f"https://www.goodreads.com/review/list_rss/{urllib.parse.quote(user)}?shelf={shelf}&page={page}"), shelf)
            if not books:
                break
            fetched.update({book["Book Id"]: book for book in books})
    if not fetched:
        raise RuntimeError(f"Goodreads' shelf feeds for user {user} are empty: the profile may be private, or the id wrong")
    # A book that left every shelf keeps its last state rather than vanishing from the index.
    state["books"].update(fetched)
    save(state_file, state)
    books = sorted(state["books"].values(), key=lambda book: int(book["Book Id"]) if book["Book Id"].isdigit() else 0)
    changed = deliver("exports", "live-goodreads.csv", csv_bytes(GOODREADS, books))
    return f"{len(books)} books on user {user}'s shelves ({how})", changed


# Spotify: recently played, the newest 50 plays, every hour, through an app of Aaron's and its refresh token.

def spotify_token(login):
    form = urllib.parse.urlencode({"grant_type": "refresh_token", "refresh_token": login["refresh_token"]}).encode()
    basic = base64.b64encode(f"{login['client_id']}:{login['client_secret']}".encode()).decode()
    answer = json.loads(request("https://accounts.spotify.com/api/token", data=form, headers={"Authorization": f"Basic {basic}", "Content-Type": "application/x-www-form-urlencoded"}))
    if answer.get("refresh_token") and answer["refresh_token"] != login["refresh_token"]:
        login["refresh_token"] = answer["refresh_token"]
        save(path("secrets", "spotify.json"), login)
    return answer["access_token"]


def spotify_play(item):
    track = item.get("track") or {}
    played = datetime.fromisoformat(item["played_at"].replace("Z", "+00:00")).astimezone(timezone.utc)
    return {
        "ts": played.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "platform": "Spotify Web API",
        "ms_played": track.get("duration_ms") or 0,
        "master_metadata_track_name": track.get("name"),
        "master_metadata_album_artist_name": ", ".join(artist.get("name", "") for artist in track.get("artists") or []) or None,
        "master_metadata_album_album_name": (track.get("album") or {}).get("name"),
        "spotify_track_uri": track.get("uri"),
        "skipped": None,
    }


def spotify():
    login = secret("spotify")
    if not login or not login.get("refresh_token"):
        raise Skip("needs Aaron's Spotify login: run sudo butler-feeds-login spotify")
    token = spotify_token(login)
    state_file = path("state", "spotify.json")
    state = load(state_file, {"plays": {}})
    answer = get_json("https://api.spotify.com/v1/me/player/recently-played?limit=50", headers={"Authorization": f"Bearer {token}"})
    new = 0
    for item in answer.get("items") or []:
        play = spotify_play(item)
        if play["master_metadata_track_name"]:
            key = f"{play['ts']}|{play['master_metadata_track_name']}"
            new += key not in state["plays"]
            state["plays"][key] = play
    save(state_file, state)
    plays = sorted(state["plays"].values(), key=lambda play: play["ts"])
    save(path("out", "spotify.json"), {"fetched": now().isoformat(timespec="seconds"), "plays": plays[-200:]}, 0o640)
    changed = deliver("spotify", "Streaming_History_Audio_live.json", json.dumps(plays, ensure_ascii=False, indent=0).encode())
    return f"{new} new plays, {len(plays)} kept", changed


# Steam: the library and playtime of Aaron's account, through a Web API key of his.

def steam():
    login = secret("steam")
    if not login or not login.get("key") or not login.get("steamid"):
        raise Skip("needs a Steam Web API key and Aaron's Steam ID: run sudo butler-feeds-login steam")
    query = urllib.parse.urlencode({"key": login["key"], "steamid": login["steamid"], "include_appinfo": 1, "include_played_free_games": 1, "format": "json"})
    owned = (get_json(f"https://api.steampowered.com/IPlayerService/GetOwnedGames/v1/?{query}").get("response") or {}).get("games") or []
    query = urllib.parse.urlencode({"key": login["key"], "steamid": login["steamid"], "format": "json"})
    recent = (get_json(f"https://api.steampowered.com/IPlayerService/GetRecentlyPlayedGames/v1/?{query}").get("response") or {}).get("games") or []
    if not owned:
        raise RuntimeError("Steam returned no games: the profile's game details may be private (Steam, Edit Profile, Privacy Settings, Game details: Public)")

    def game(entry):
        last = entry.get("rtime_last_played") or 0
        return {
            "appid": entry.get("appid"),
            "name": entry.get("name") or str(entry.get("appid")),
            "hours": round((entry.get("playtime_forever") or 0) / 60, 1),
            "hours_2weeks": round((entry.get("playtime_2weeks") or 0) / 60, 1),
            "last_played": datetime.fromtimestamp(last, LOCAL).date().isoformat() if last else "",
        }

    games = sorted((game(entry) for entry in owned), key=lambda item: (-item["hours"], item["name"].lower()))
    recent_games = [game(entry) for entry in recent]
    save(path("out", "steam.json"), {"fetched": now().isoformat(timespec="seconds"), "games": games, "recent": recent_games}, 0o640)
    rows = [{"Game": item["name"], "App ID": item["appid"], "Hours played": item["hours"], "Hours in the last two weeks": item["hours_2weeks"], "Last played": item["last_played"]} for item in games]
    changed = deliver("exports", "live-steam-library.csv", csv_bytes(["Game", "App ID", "Hours played", "Hours in the last two weeks", "Last played"], rows))
    return f"{len(games)} games, {len(recent_games)} played in the last two weeks", changed


# PayPal: the transaction search of Aaron's own account, through a REST app of his with Transaction Search enabled.

PAYPAL = ["Date", "Time", "TimeZone", "Name", "Type", "Status", "Currency", "Amount", "Transaction ID", "Item Title"]
PAYPAL_TYPES = {
    "T00": "Payment",
    "T01": "Fee",
    "T02": "Currency conversion",
    "T03": "Bank deposit",
    "T04": "Bank withdrawal",
    "T05": "Debit card",
    "T06": "Credit card",
    "T07": "Payment",
    "T08": "Reward",
    "T09": "Gift",
    "T11": "Refund",
    "T12": "Dispute",
    "T13": "Reversal",
    "T15": "Authorisation hold",
    "T17": "Payment",
    "T19": "Adjustment",
    "T20": "Payout",
    "T22": "Subscription",
}
PAYPAL_STATUS = {"S": "Completed", "P": "Pending", "V": "Reversed", "D": "Denied", "F": "Partially refunded"}


def paypal_token(login):
    base = "https://api-m.sandbox.paypal.com" if login.get("environment") == "sandbox" else "https://api-m.paypal.com"
    basic = base64.b64encode(f"{login['client_id']}:{login['client_secret']}".encode()).decode()
    answer = json.loads(request(f"{base}/v1/oauth2/token", data=b"grant_type=client_credentials", headers={"Authorization": f"Basic {basic}", "Content-Type": "application/x-www-form-urlencoded"}))
    return base, answer["access_token"]


def paypal_row(detail):
    info = detail.get("transaction_info") or {}
    payer = (detail.get("payer_info") or {}).get("payer_name") or {}
    items = [item.get("item_name") for item in (detail.get("cart_info") or {}).get("item_details") or [] if item.get("item_name")]
    moment = datetime.fromisoformat(info["transaction_initiation_date"].replace("Z", "+00:00").replace("+0000", "+00:00")).astimezone(LOCAL)
    amount = info.get("transaction_amount") or {}
    name = payer.get("alternate_full_name") or " ".join(filter(None, [payer.get("given_name"), payer.get("surname")])) or info.get("transaction_subject") or (items[0] if items else "") or "PayPal"
    return {
        "Date": moment.strftime("%d/%m/%Y"),
        "Time": moment.strftime("%H:%M:%S"),
        "TimeZone": "Australia/Melbourne",
        "Name": name,
        "Type": PAYPAL_TYPES.get((info.get("transaction_event_code") or "")[:3], info.get("transaction_event_code") or "Payment"),
        "Status": PAYPAL_STATUS.get(info.get("transaction_status"), info.get("transaction_status") or ""),
        "Currency": amount.get("currency_code") or "",
        "Amount": amount.get("value") or "",
        "Transaction ID": info.get("transaction_id") or "",
        "Item Title": ", ".join(items)[:300] or info.get("transaction_subject") or "",
    }


def paypal():
    login = secret("paypal")
    if not login or not login.get("client_id") or not login.get("client_secret"):
        raise Skip("needs a PayPal REST app of Aaron's with Transaction Search: run sudo butler-feeds-login paypal")
    base, token = paypal_token(login)
    state_file = path("state", "paypal.json")
    state = load(state_file, {"rows": {}})
    end = now().replace(microsecond=0)
    start = datetime.fromisoformat(state["through"]) - timedelta(days=3) if state.get("through") else end - timedelta(days=365 * 3 - 2)
    while start < end:
        stop = min(start + timedelta(days=31), end)
        for page in range(1, 51):
            query = urllib.parse.urlencode({"start_date": start.strftime("%Y-%m-%dT%H:%M:%SZ"), "end_date": stop.strftime("%Y-%m-%dT%H:%M:%SZ"), "fields": "transaction_info,payer_info,cart_info", "page_size": 500, "page": page})
            answer = get_json(f"{base}/v1/reporting/transactions?{query}", headers={"Authorization": f"Bearer {token}"})
            for detail in answer.get("transaction_details") or []:
                row = paypal_row(detail)
                if row["Transaction ID"]:
                    state["rows"][f"{row['Transaction ID']}:{row['Type']}"] = row
            if page >= (answer.get("total_pages") or 1):
                break
        start = stop
    state["through"] = end.isoformat()
    save(state_file, state)
    exported = set()
    for file_path in others("paypal", "live-paypal.csv"):
        for _, data in members(file_path):
            exported |= {row.get("Transaction ID") for row in csv_rows(data)}
    rows = sorted((row for row in state["rows"].values() if row["Transaction ID"] not in exported), key=lambda row: (row["Date"][6:] + row["Date"][3:5] + row["Date"][:2], row["Time"], row["Transaction ID"]))
    changed = deliver("paypal", "live-paypal.csv", csv_bytes(PAYPAL, rows))
    return f"{len(rows)} transactions newer than the export", changed


# Mail: Hostplus and CMC statements attached to mail, and Uber and Amazon receipts, from every account's inbox and archive.

MAIL_RULES = {
    "hostplus": {"query": ["from", "hostplus"], "attachments": (".pdf",)},
    "cmc": {"query": ["(", "from", "cmcmarkets", "or", "from", "cmcinvest", ")"], "attachments": (".pdf", ".csv")},
    "uber": {"query": ["from", "uber.com"], "subject": r"(?i)\btrip\b|\border\b|receipt"},
    "amazon": {"query": ["from", "amazon"], "subject": r"(?i)\border"},
}
UBER_TRIPS = ["request_timestamp_utc", "status", "product_type_name", "begintrip_string", "destination_string", "city_name", "original_fare_local", "currency_code"]
UBER_EATS = ["Order_UUID", "Order_Status", "Restaurant_Name", "Item_quantity", "Item_Name", "Order_Price", "Currency", "Request_Time_Local"]
AMAZON = ["Order ID", "Order Date", "Product Name", "Total Amount", "Currency", "ASIN", "Order Status", "Shipment Status"]
MONEY = r"(?:A\$|AU\$|AUD\s?|\$)\s?([\d,]+\.\d{2})"


def himalaya(*args):
    result = subprocess.run([CONFIG["himalaya"], "--config", CONFIG["himalayaConfig"], "--log-level", "off", *args], capture_output=True, timeout=300)
    if result.returncode != 0:
        raise RuntimeError((result.stderr or result.stdout).decode(errors="replace").strip()[:300] or f"himalaya exited {result.returncode}")
    return result.stdout


def mail_search(account, mailbox, query, since):
    envelopes = []
    for page in range(1, 11):
        out = himalaya("--json", "--account", account, "envelope", "search", "--mailbox", mailbox, "--page", str(page), "--page-size", "200", *query, "and", "after", since, "order", "by", "date", "desc")
        batch = json.loads(out)
        batch = batch.get("envelopes", []) if isinstance(batch, dict) else batch
        envelopes += batch
        if len(batch) < 200:
            break
    return envelopes


def message_parts(raw):
    message = email.message_from_bytes(raw, policy=email.policy.default)
    plain, markup, attachments = [], [], []
    for part in message.walk():
        if part.is_multipart():
            continue
        name = part.get_filename()
        kind = part.get_content_type()
        if name:
            attachments.append((name, part.get_payload(decode=True) or b""))
        elif kind == "text/plain":
            plain.append(part.get_content())
        elif kind == "text/html":
            markup.append(part.get_content())
    text = "\n".join(plain) if plain and sum(len(p) for p in plain) > 200 else text_of("\n".join(markup)) or "\n".join(plain)
    return message, text, attachments


def safe_name(name):
    name = re.sub(r"[^A-Za-z0-9._ ()+,-]+", "-", name).strip(" .-") or "file"
    return name[-120:]


def uber_receipt(message, subject, text, moment):
    total = re.search(r"(?im)^\s*Total\s*:?\s*" + MONEY, text) or re.search(r"(?i)\bTotal\b[^\n$]{0,20}" + MONEY, text)
    if not total:
        return None
    amount = total.group(1).replace(",", "")
    if re.search(r"(?i)uber\s*eats|your order|order from", subject + " " + text[:300]):
        restaurant = re.search(r"(?i)order (?:with|from) (.+?)(?:\s*[.!]|$)", subject) or re.search(r"(?im)^(?:you ordered from|order from)\s+(.+)$", text)
        items = re.findall(r"(?m)^(\d{1,2})\s*[x×]?\s+([^\n$]{2,80}?)\s+" + MONEY + r"\s*$", text)
        return "eats", [
            {
                "Order_UUID": hashlib.sha256((message.get("Message-ID") or subject + moment.isoformat()).encode()).hexdigest()[:32],
                "Order_Status": "completed",
                "Restaurant_Name": (restaurant.group(1).strip() if restaurant else "Uber Eats")[:120],
                "Item_quantity": quantity,
                "Item_Name": name.strip()[:120],
                "Order_Price": amount,
                "Currency": "AUD",
                "Request_Time_Local": moment.astimezone(LOCAL).strftime("%Y-%m-%d %H:%M:%S"),
            }
            for quantity, name, _ in (items or [("1", "order", amount)])
        ]
    stops = re.findall(r"(?im)^\s*\d{1,2}:\d{2}\s*(?:am|pm)?\s*[|·-]?\s*(.{6,120})$", text)
    product = re.search(r"(?i)\b(UberX|Uber\s?XL|Comfort|Uber Green|Uber Black|Premier|Uber Pet|UberX Share|Taxi|Uber Moto)\b", text)
    return "trip", [
        {
            "request_timestamp_utc": moment.astimezone(timezone.utc).strftime("%Y-%m-%d %H:%M:%S +0000 UTC"),
            "status": "completed",
            "product_type_name": product.group(1) if product else "Uber",
            "begintrip_string": stops[0].strip() if stops else "",
            "destination_string": stops[-1].strip() if len(stops) > 1 else "",
            "city_name": "",
            "original_fare_local": amount,
            "currency_code": "AUD",
        }
    ]


def amazon_receipt(subject, text, moment):
    order = re.search(r"\b(\d{3}-\d{7}-\d{7})\b", subject + "\n" + text)
    if not order or not re.search(r"(?i)\border(ed)?\b", subject) or re.search(r"(?i)shipped|dispatched|delivered|out for delivery|arriving|refund|return|cancel", subject):
        return None
    product = re.search(r"(?i)ordered:\s*[\"“](.+?)[\"”]", subject) or re.search(r"(?i)order of\s+[\"“]?(.+?)[\"”]?\s*(?:\.\.\.|…)?$", subject)
    total = re.search(r"(?i)(?:order total|grand total|total)\s*:?\s*" + MONEY, text)
    return {
        "Order ID": order.group(1),
        "Order Date": moment.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "Product Name": (product.group(1).strip() if product else subject.strip())[:300],
        "Total Amount": total.group(1).replace(",", "") if total else "",
        "Currency": "AUD",
        "ASIN": "",
        "Order Status": "Ordered",
        "Shipment Status": "",
    }


def export_cutoff(folder, columns):
    latest = ""
    for file_path in others(folder, ""):
        for _, data in members(file_path):
            for row in csv_rows(data):
                for column in columns:
                    if row.get(column):
                        latest = max(latest, row[column][:19].replace("T", " "))
    return latest


def mail():
    accounts = CONFIG.get("mailAccounts") or {}
    if not accounts:
        raise Skip("no mail accounts are configured on spike")
    state_file = path("state", "mail.json")
    state = load(state_file, {"seen": [], "trips": [], "eats": [], "amazon": [], "files": []})
    seen = set(state["seen"])
    since = (datetime.fromisoformat(state["through"]) - timedelta(days=3)) if state.get("through") else now() - timedelta(days=MAIL_LOOKBACK_DAYS)
    since_text = since.astimezone(LOCAL).date().isoformat()
    counts = {rule: 0 for rule in MAIL_RULES}
    errors = []
    for account, mailboxes in accounts.items():
        for mailbox in mailboxes:
            for rule, spec in MAIL_RULES.items():
                try:
                    envelopes = mail_search(account, mailbox, spec["query"], since_text)
                except (RuntimeError, ValueError, subprocess.TimeoutExpired) as error:
                    errors.append(f"{account} {mailbox} {rule}: {error}")
                    continue
                for envelope in envelopes:
                    key = envelope.get("message-id") or f"{account}:{mailbox}:{envelope.get('id')}"
                    if f"{rule}|{key}" in seen:
                        continue
                    if "subject" in spec and not re.search(spec["subject"], envelope.get("subject") or ""):
                        seen.add(f"{rule}|{key}")
                        continue
                    try:
                        raw = himalaya("--account", account, "message", "read", "--mailbox", mailbox, "--raw", str(envelope["id"]))
                    except (RuntimeError, subprocess.TimeoutExpired) as error:
                        errors.append(f"{account} {rule}: {error}")
                        continue
                    message, text, attachments = message_parts(raw)
                    subject = str(message.get("Subject") or envelope.get("subject") or "")
                    try:
                        moment = parsedate_to_datetime(message.get("Date"))
                    except (TypeError, ValueError):
                        moment = now()
                    if moment.tzinfo is None:
                        moment = moment.replace(tzinfo=timezone.utc)
                    if "attachments" in spec:
                        for name, data in attachments:
                            if name.lower().endswith(spec["attachments"]) and data:
                                stamp = moment.astimezone(LOCAL).date().isoformat()
                                target = f"live-{rule}-{stamp}-{hashlib.sha256(data).hexdigest()[:8]}-{safe_name(name)}"
                                if deliver("exports", target, data):
                                    state["files"].append(target)
                                counts[rule] += 1
                    elif rule == "uber":
                        receipt = uber_receipt(message, subject, text, moment)
                        if receipt:
                            state["trips" if receipt[0] == "trip" else "eats"] += receipt[1]
                            counts[rule] += 1
                    elif rule == "amazon":
                        receipt = amazon_receipt(subject, text, moment)
                        if receipt and receipt["Order ID"] not in {row["Order ID"] for row in state["amazon"]}:
                            state["amazon"].append(receipt)
                            counts[rule] += 1
                    seen.add(f"{rule}|{key}")
                # Saved after each search, so a first run cut off by its timeout carries on where it stopped.
                state["seen"] = sorted(seen)[-SEEN_CAP:]
                save(state_file, state)
    state["seen"] = sorted(seen)[-SEEN_CAP:]
    if not errors:
        state["through"] = now().isoformat()
    save(state_file, state)
    uber_after = export_cutoff("uber", ["request_timestamp_utc", "Request_Time_Local"])
    trips = [row for row in state["trips"] if row["request_timestamp_utc"][:19] > uber_after]
    eats = [row for row in state["eats"] if row["Request_Time_Local"][:19] > uber_after]
    deliver("uber", "live-rider_lifetime_trips-0.csv", csv_bytes(UBER_TRIPS, trips))
    deliver("uber", "live-eats_order_details-0.csv", csv_bytes(UBER_EATS, eats))
    exported_orders = set()
    for file_path in others("amazon", ""):
        for _, data in members(file_path):
            exported_orders |= {row.get("Order ID") for row in csv_rows(data)}
    deliver("amazon", "live-Order History.csv", csv_bytes(AMAZON, [row for row in state["amazon"] if row["Order ID"] not in exported_orders]))
    summary = ", ".join(f"{counts[rule]} new {rule}" for rule in MAIL_RULES)
    if errors:
        raise RuntimeError(f"{summary}; some searches failed: " + "; ".join(errors[:3]))
    return summary, True


RUNNERS = {"letterboxd": letterboxd, "goodreads": goodreads, "spotify": spotify, "steam": steam, "paypal": paypal, "mail": mail}


def run(names):
    status_file = path("out", "status.json")
    status = load(status_file, {})
    failed = False
    for name in names or FEEDS:
        entry = status.get(name, {})
        entry["checked"] = now().isoformat(timespec="seconds")
        try:
            message, changed = RUNNERS[name]()
            entry.update(state="connected", message=message, ok=entry["checked"])
            if changed:
                entry["delivered"] = entry["checked"]
        except Skip as reason:
            entry.update(state="needs-login", message=str(reason))
        except (OSError, ValueError, KeyError, RuntimeError, ElementTree.ParseError, urllib.error.URLError, subprocess.SubprocessError) as error:
            detail = f"HTTP {error.code}" if isinstance(error, urllib.error.HTTPError) else f"{error.__class__.__name__}: {error}"
            entry.update(state="failing", message=re.sub(r"(key|token|secret)=[^&\s]+", r"\1=…", detail)[:300])
            failed = True
        status[name] = entry
        print(f"{name}: {entry['state']}: {entry['message']}")
    save(status_file, status, 0o640)
    return 1 if failed and len(names or FEEDS) == 1 else 0


# What butler reads, through its `feeds` command: no login and no secret, only the status and the feeds' own snapshots.

def show_status():
    status = load(path("out", "status.json"), {})
    for name in FEEDS:
        entry = status.get(name)
        if not entry:
            print(f"{name}: not run yet")
            continue
        print(f"{name}: {entry.get('state')} (checked {entry.get('checked')}, last good {entry.get('ok') or 'never'}): {entry.get('message')}")


def show_steam(args):
    snapshot = load(path("out", "steam.json"), None)
    if not snapshot:
        print("steam: no library read yet; Aaron has to run sudo butler-feeds-login steam on spike", file=sys.stderr)
        return 78
    mode = args[0] if args and args[0] in ("recent", "library") else "library"
    words = [word.lower() for word in (args[1:] if args and args[0] in ("recent", "library") else args)]
    games = snapshot["recent"] if mode == "recent" else snapshot["games"]
    games = [game for game in games if all(word in game["name"].lower() for word in words)]
    print(json.dumps({"fetched": snapshot["fetched"], "count": len(games), "games": games[:100]}, ensure_ascii=False, indent=1))
    return 0


def show_spotify(args):
    snapshot = load(path("out", "spotify.json"), None)
    if not snapshot:
        print("spotify: no plays read yet; Aaron has to run sudo butler-feeds-login spotify on spike", file=sys.stderr)
        return 78
    count = int(args[0]) if args and args[0].isdigit() else 20
    plays = [{"ts": play["ts"], "track": play["master_metadata_track_name"], "artist": play["master_metadata_album_artist_name"], "album": play["master_metadata_album_album_name"]} for play in snapshot["plays"][-min(count, 200):]]
    print(json.dumps({"fetched": snapshot["fetched"], "plays": list(reversed(plays))}, ensure_ascii=False, indent=1))
    return 0


# Logins, run by Aaron on spike as root, which drops to butler: secrets are typed hidden and written to secrets/, mode 600.

def ask(prompt, hidden=False):
    value = (getpass.getpass(prompt) if hidden else input(prompt)).strip()
    if not value:
        raise SystemExit("nothing entered; nothing changed")
    return value


def login(feed, args):
    if feed in ("letterboxd", "goodreads"):
        value = args[0] if args else ask(f"{feed} {'username' if feed == 'letterboxd' else 'user id (the number in your profile address)'}: ")
        if not re.fullmatch(r"[A-Za-z0-9_.-]{1,60}" if feed == "letterboxd" else r"\d{1,15}", value):
            raise SystemExit(f"that does not look like a {feed} {'username' if feed == 'letterboxd' else 'user id'}")
        config = settings()
        config[feed] = value
        save(path("config.json"), config)
    elif feed == "spotify":
        print("Make an app at https://developer.spotify.com/dashboard with the redirect URI", SPOTIFY_REDIRECT, "and the Web API ticked.")
        client_id = ask("Client ID: ")
        client_secret = ask("Client secret (hidden): ", hidden=True)
        nonce = secrets.token_urlsafe(16)
        print("\nOpen this in a browser signed in to your Spotify account and agree:\n")
        print("https://accounts.spotify.com/authorize?" + urllib.parse.urlencode({"client_id": client_id, "response_type": "code", "redirect_uri": SPOTIFY_REDIRECT, "scope": SPOTIFY_SCOPE, "state": nonce}))
        print("\nThe browser then fails to load 127.0.0.1:8888; that is expected. Paste the whole address it shows.")
        address = urllib.parse.urlsplit(ask("Address: "))
        query = dict(urllib.parse.parse_qsl(address.query))
        if query.get("state") != nonce or not query.get("code"):
            raise SystemExit("that address does not carry this login's code; nothing changed")
        form = urllib.parse.urlencode({"grant_type": "authorization_code", "code": query["code"], "redirect_uri": SPOTIFY_REDIRECT}).encode()
        basic = base64.b64encode(f"{client_id}:{client_secret}".encode()).decode()
        answer = json.loads(request("https://accounts.spotify.com/api/token", data=form, headers={"Authorization": f"Basic {basic}", "Content-Type": "application/x-www-form-urlencoded"}))
        save(path("secrets", "spotify.json"), {"client_id": client_id, "client_secret": client_secret, "refresh_token": answer["refresh_token"]})
    elif feed == "steam":
        print("Get a key at https://steamcommunity.com/dev/apikey (any domain name, such as spike.local).")
        key = ask("Steam Web API key (hidden): ", hidden=True)
        who = ask("Your Steam ID (17 digits) or profile address or custom URL name: ")
        match = re.search(r"(\d{17})", who)
        if match:
            steamid = match.group(1)
        else:
            vanity = re.sub(r"^.*/id/", "", who).strip("/")
            answer = get_json("https://api.steampowered.com/ISteamUser/ResolveVanityURL/v1/?" + urllib.parse.urlencode({"key": key, "vanityurl": vanity}))
            steamid = (answer.get("response") or {}).get("steamid")
            if not steamid:
                raise SystemExit("Steam could not find that profile; nothing changed")
        save(path("secrets", "steam.json"), {"key": key, "steamid": steamid})
    elif feed == "paypal":
        print("Make a Live REST app at https://developer.paypal.com/dashboard/applications with Transaction search ticked under its features.")
        client_id = ask("Client ID: ")
        client_secret = ask("Secret (hidden): ", hidden=True)
        login_data = {"client_id": client_id, "client_secret": client_secret, "environment": "live"}
        paypal_token(login_data)
        save(path("secrets", "paypal.json"), login_data)
    else:
        raise SystemExit(f"usage: butler-feeds-login {'|'.join(FEEDS[:5])}")
    print(f"{feed}: saved; fetching now")
    return run([feed])


def main(argv):
    command, args = (argv[1], argv[2:]) if len(argv) > 1 else ("", [])
    if command == "run":
        unknown = [name for name in args if name not in FEEDS]
        if unknown:
            raise SystemExit(f"unknown feeds: {' '.join(unknown)}")
        return run(args)
    if command == "status":
        show_status()
        return 0
    if command == "steam":
        return show_steam(args)
    if command == "spotify":
        return show_spotify(args)
    if command == "login" and args:
        return login(args[0], args[1:])
    print("usage: feeds status | feeds steam [recent|library] [words...] | feeds spotify [count]", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
