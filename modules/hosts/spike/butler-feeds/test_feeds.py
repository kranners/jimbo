"""Runs butler-feeds against fixture answers offline: each feed's inbox file, the overlap with an export left out, and status."""

import csv
import importlib.util
import io
import json
import os
import sys
import tempfile
import zipfile
from email.message import EmailMessage

root = tempfile.mkdtemp()
state, inbox = os.path.join(root, "state"), os.path.join(root, "inbox")
for folder in ("exports", "spotify", "paypal", "uber", "amazon"):
    os.makedirs(os.path.join(inbox, folder))
for folder in ("secrets", "state", "out"):
    os.makedirs(os.path.join(state, folder))
os.environ["BUTLER_FEEDS_CONFIG_JSON"] = json.dumps(
    {"stateDir": state, "inbox": inbox, "indexDb": os.path.join(root, "none.sqlite"), "himalaya": "himalaya", "himalayaConfig": "x", "mailAccounts": {"fastmail": ["inbox"]}, "timeZone": "UTC"}
)
spec = importlib.util.spec_from_file_location("feeds", sys.argv[1])
feeds = importlib.util.module_from_spec(spec)
spec.loader.exec_module(feeds)


def check(condition, message):
    if not condition:
        raise SystemExit(f"FAIL: {message}")
    print(f"ok: {message}")


def secret(name, data):
    with open(os.path.join(state, "secrets", f"{name}.json"), "w") as handle:
        json.dump(data, handle)


# An export already in the inbox: its profile names the user, and its diary entry must not be repeated.
export = io.BytesIO()
with zipfile.ZipFile(export, "w") as archive:
    archive.writestr("profile.csv", "Date Joined,Username,Given Name\n2020-01-01,filmfan,A\n")
    archive.writestr("diary.csv", "Date,Name,Year,Letterboxd URI,Rating,Rewatch,Tags,Watched Date\n2026-10-01,Old Film,1999,https://boxd.it/a,4,,,2026-10-01\n")
with open(os.path.join(inbox, "exports", "letterboxd-filmfan-2026-10-02.zip"), "wb") as handle:
    handle.write(export.getvalue())

LETTERBOXD = b"""<?xml version="1.0"?><rss xmlns:letterboxd="https://letterboxd.com" version="2.0"><channel>
<item><title>Old Film, 1999</title><link>https://letterboxd.com/filmfan/film/old-film/</link><pubDate>Thu, 01 Oct 2026 10:00:00 +1000</pubDate>
<letterboxd:watchedDate>2026-10-01</letterboxd:watchedDate><letterboxd:filmTitle>Old Film</letterboxd:filmTitle><letterboxd:filmYear>1999</letterboxd:filmYear></item>
<item><title>New Film, 2026</title><link>https://letterboxd.com/filmfan/film/new-film/</link><pubDate>Mon, 02 Nov 2026 10:00:00 +1000</pubDate>
<letterboxd:watchedDate>2026-11-01</letterboxd:watchedDate><letterboxd:rewatch>No</letterboxd:rewatch><letterboxd:filmTitle>New Film</letterboxd:filmTitle>
<letterboxd:filmYear>2026</letterboxd:filmYear><letterboxd:memberRating>4.5</letterboxd:memberRating>
<description><![CDATA[<p><img src="x.jpg"/></p><p>Loved it.</p>]]></description></item>
<item><title>A list</title><link>https://letterboxd.com/filmfan/list/x/</link></item>
</channel></rss>"""

GOODREADS = b"""<?xml version="1.0"?><rss version="2.0"><channel>
<item><title>A Book</title><book_id>42</book_id><author_name>Some Author</author_name><user_rating>5</user_rating><average_rating>4.1</average_rating>
<user_read_at>Sun, 01 Nov 2026 00:00:00 -0700</user_read_at><user_date_added>Sat, 01 Aug 2026 00:00:00 -0700</user_date_added><user_shelves>favourites</user_shelves>
<isbn>9780000000002</isbn><book_published>2001</book_published><user_review></user_review><book><num_pages>300</num_pages></book></item>
</channel></rss>"""

SPOTIFY = {"items": [{"played_at": "2026-11-05T03:02:01.123Z", "track": {"name": "Song", "duration_ms": 200000, "uri": "spotify:track:1", "artists": [{"name": "Band"}], "album": {"name": "Album"}}}]}
STEAM_OWNED = {"response": {"games": [{"appid": 10, "name": "Game One", "playtime_forever": 600, "rtime_last_played": 1700000000}, {"appid": 20, "name": "Game Two", "playtime_forever": 30, "playtime_2weeks": 30}]}}
STEAM_RECENT = {"response": {"games": [{"appid": 20, "name": "Game Two", "playtime_forever": 30, "playtime_2weeks": 30}]}}
PAYPAL = {
    "total_pages": 1,
    "transaction_details": [
        {"transaction_info": {"transaction_id": "OLD1", "transaction_event_code": "T0006", "transaction_initiation_date": "2026-01-01T01:00:00+0000", "transaction_amount": {"currency_code": "AUD", "value": "-5.00"}, "transaction_status": "S"}, "payer_info": {"payer_name": {"alternate_full_name": "Shop"}}},
        {"transaction_info": {"transaction_id": "NEW1", "transaction_event_code": "T0006", "transaction_initiation_date": "2026-11-01T01:00:00+0000", "transaction_amount": {"currency_code": "AUD", "value": "-12.50"}, "transaction_status": "S"}, "payer_info": {"payer_name": {"alternate_full_name": "Store"}}, "cart_info": {"item_details": [{"item_name": "Widget"}]}},
    ],
}
calls = []


def fake_request(url, data=None, headers=None, method=None, timeout=60):
    calls.append(url)
    if "letterboxd.com/filmfan/rss" in url:
        return LETTERBOXD
    if "goodreads.com" in url:
        return GOODREADS if "shelf=read&page=1" in url else b"<rss><channel></channel></rss>"
    if "accounts.spotify.com" in url:
        return json.dumps({"access_token": "a", "refresh_token": "rotated"}).encode()
    if "recently-played" in url:
        return json.dumps(SPOTIFY).encode()
    if "GetOwnedGames" in url:
        return json.dumps(STEAM_OWNED).encode()
    if "GetRecentlyPlayed" in url:
        return json.dumps(STEAM_RECENT).encode()
    if "oauth2/token" in url:
        return json.dumps({"access_token": "p"}).encode()
    if "reporting/transactions" in url:
        return json.dumps(PAYPAL).encode()
    raise AssertionError(f"unexpected request {url}")


def mail_message(sender, subject, body, attachment=None):
    message = EmailMessage()
    message["From"], message["Subject"], message["Date"], message["Message-ID"] = sender, subject, "Tue, 03 Nov 2026 09:00:00 +0000", f"<{subject}@x>"
    message.set_content(body)
    if attachment:
        message.add_attachment(attachment[1], maintype="application", subtype="pdf", filename=attachment[0])
    return message.as_bytes()


MAIL = {
    "hostplus": [mail_message("statements@hostplus.com.au", "Your statement", "Attached.", ("Statement FY26.pdf", b"%PDF-1.4 fixture"))],
    "cmcmarkets": [],
    "uber.com": [
        mail_message("noreply@uber.com", "Your Tuesday morning trip with Uber", "UberX\nTotal A$23.45\n8:01 am | 1 Home St, Collingwood\n8:20 am | 2 Work Rd, Melbourne\n" + "x" * 200),
        mail_message("noreply@uber.com", "Your Uber Eats order with Taco Place", "Total A$31.00\n2 Tacos A$20.00\n1 Drink A$11.00\n" + "x" * 200),
        mail_message("noreply@uber.com", "Promo for you", "No total here " + "x" * 200),
    ],
    "amazon": [
        mail_message("auto-confirm@amazon.com.au", 'Ordered: "Cable, 2 m"', "Order # 123-1234567-1234567\nOrder Total: A$15.99\n" + "x" * 200),
        mail_message("shipment-tracking@amazon.com.au", "Your order has shipped", "Order # 123-1234567-1234567\n" + "x" * 200),
    ],
}
stored = {}


def fake_himalaya(*args):
    if "search" in args:
        word = args[args.index("from") + 1]
        envelopes = []
        for number, raw in enumerate(MAIL.get(word, [])):
            key = f"{word}-{number}"
            stored[key] = raw
            subject = raw.split(b"Subject: ", 1)[1].split(b"\n", 1)[0].decode()
            envelopes.append({"id": key, "message-id": f"<{key}>", "subject": subject})
        return json.dumps({"envelopes": envelopes}).encode()
    return stored[args[-1]]


feeds.request = fake_request
feeds.himalaya = fake_himalaya


def inbox_file(*parts):
    with open(os.path.join(inbox, *parts), "rb") as handle:
        return handle.read()


def rows(data):
    return list(csv.DictReader(io.StringIO(data.decode())))


# Nothing logged in yet: the login feeds wait and say how, and the public ones find their user.
os.environ.pop("unused", None)
feeds.run(["spotify", "steam", "paypal"])
status = json.load(open(os.path.join(state, "out", "status.json")))
check(all(status[name]["state"] == "needs-login" for name in ("spotify", "steam", "paypal")), "login feeds wait for a login and say so")
check("butler-feeds-login spotify" in status["spotify"]["message"], "the waiting feed names its login helper")
feeds.run(["goodreads"])
check(json.load(open(os.path.join(state, "out", "status.json")))["goodreads"]["state"] == "needs-login", "goodreads without a user id or browser history waits")

feeds.run(["letterboxd"])
with zipfile.ZipFile(io.BytesIO(inbox_file("exports", "live-letterboxd.zip"))) as archive:
    diary = rows(archive.read("diary.csv"))
    reviews = rows(archive.read("reviews.csv"))
check([row["Name"] for row in diary] == ["New Film"], "letterboxd keeps the RSS entry the export lacks and drops the one it has, and lists")
check(diary[0]["Rating"] == "4.5" and diary[0]["Watched Date"] == "2026-11-01", "letterboxd's rating and watched date are kept")
check(reviews and reviews[0]["Review"] == "Loved it.", "letterboxd's review text is kept without the poster")
before = os.path.getmtime(os.path.join(inbox, "exports", "live-letterboxd.zip"))
feeds.run(["letterboxd"])
check(os.path.getmtime(os.path.join(inbox, "exports", "live-letterboxd.zip")) == before, "an unchanged feed leaves its inbox file alone")

with open(os.path.join(state, "config.json"), "w") as handle:
    json.dump({"goodreads": "1234"}, handle)
feeds.run(["goodreads"])
books = rows(inbox_file("exports", "live-goodreads.csv"))
check(books[0]["Book Id"] == "42" and books[0]["Exclusive Shelf"] == "read" and books[0]["Date Read"] == "2026/11/01", "goodreads writes the library export's columns")
check({"Book Id", "Title", "Exclusive Shelf"} <= set(books[0]), "goodreads' file carries the header the index reader knows it by")

secret("spotify", {"client_id": "c", "client_secret": "s", "refresh_token": "r"})
feeds.run(["spotify"])
plays = json.loads(inbox_file("spotify", "Streaming_History_Audio_live.json"))
check(plays[0]["ts"] == "2026-11-05T03:02:01Z" and plays[0]["ms_played"] == 200000, "spotify writes plays in the streaming history's shape")
check(json.load(open(os.path.join(state, "secrets", "spotify.json")))["refresh_token"] == "rotated", "spotify keeps a rotated refresh token")

secret("steam", {"key": "k", "steamid": "76561190000000000"})
feeds.run(["steam"])
library = rows(inbox_file("exports", "live-steam-library.csv"))
check(library[0]["Game"] == "Game One" and library[0]["Hours played"] == "10.0", "steam writes the library by hours played")

with open(os.path.join(inbox, "paypal", "Download.CSV"), "w") as handle:
    handle.write("Date,Time,Name,Type,Status,Currency,Amount,Transaction ID\n01/01/2026,12:00:00,Shop,Payment,Completed,AUD,-5.00,OLD1\n")
secret("paypal", {"client_id": "c", "client_secret": "s", "environment": "live"})
feeds.run(["paypal"])
payments = rows(inbox_file("paypal", "live-paypal.csv"))
check([row["Transaction ID"] for row in payments] == ["NEW1"], "paypal leaves out transactions the activity export already holds")
check(payments[0]["Date"] == "01/11/2026" and payments[0]["Name"] == "Store" and payments[0]["Item Title"] == "Widget", "paypal writes the activity CSV's columns")

feeds.run(["mail"])
status = json.load(open(os.path.join(state, "out", "status.json")))
check(status["mail"]["state"] == "connected", f"mail runs: {status['mail']['message']}")
check(any(name.startswith("live-hostplus-2026-11-03-") and name.endswith("Statement FY26.pdf") for name in os.listdir(os.path.join(inbox, "exports"))), "a Hostplus statement attachment lands in exports, named for its reader")
trips = rows(inbox_file("uber", "live-rider_lifetime_trips-0.csv"))
check(len(trips) == 1 and trips[0]["original_fare_local"] == "23.45" and trips[0]["destination_string"] == "2 Work Rd, Melbourne", "an Uber trip receipt becomes a trip with its fare and stops")
eats = rows(inbox_file("uber", "live-eats_order_details-0.csv"))
check({row["Item_Name"] for row in eats} == {"Tacos", "Drink"} and eats[0]["Restaurant_Name"] == "Taco Place", "an Uber Eats receipt becomes an order with its items")
orders = rows(inbox_file("amazon", "live-Order History.csv"))
check(len(orders) == 1 and orders[0]["Product Name"] == "Cable, 2 m" and orders[0]["Total Amount"] == "15.99", "an Amazon order confirmation becomes one order, its shipment mail ignored")

feeds.show_status()
print("all butler-feeds checks passed")
