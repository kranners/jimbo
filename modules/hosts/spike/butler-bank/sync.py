import json
import os
import pwd
import sqlite3
from datetime import datetime, timezone
from pathlib import Path
from urllib.request import Request, urlopen

API = "https://api.up.com.au/api/v1"
DATABASE = Path(pwd.getpwuid(os.getuid()).pw_dir) / "bank" / "up.sqlite"
TOKEN = (Path(os.environ["CREDENTIALS_DIRECTORY"]) / "up-token").read_text().strip()

SCHEMA = """
create table accounts (
  name text primary key,
  type text,
  ownership text,
  balance real
);
create table transactions (
  id text primary key,
  created_at text,
  created_on text,
  settled_at text,
  account text,
  status text,
  description text,
  message text,
  raw_text text,
  amount real,
  foreign_amount real,
  foreign_currency text,
  category text,
  parent_category text,
  tags text,
  transfer_account text
);
create index transactions_created_on on transactions (created_on);
create table synced (at text);
"""


def get(url):
    request = Request(url, headers={"Authorization": "Bearer " + TOKEN})
    with urlopen(request, timeout=60) as response:
        return json.load(response)


def pages(url):
    while url:
        page = get(url)
        yield from page["data"]
        url = page["links"]["next"]


def dollars(money):
    return money["valueInBaseUnits"] / 100 if money else None


def related(relationships, name):
    return (relationships.get(name, {}).get("data") or {}).get("id")


def main():
    partial = DATABASE.with_suffix(".partial")
    partial.unlink(missing_ok=True)

    database = sqlite3.connect(partial)
    database.executescript(SCHEMA)

    names = {}
    for account in pages(API + "/accounts?page[size]=100"):
        a = account["attributes"]
        names[account["id"]] = a["displayName"]
        database.execute(
            "insert into accounts values (?, ?, ?, ?)",
            (a["displayName"], a["accountType"], a["ownershipType"], dollars(a["balance"])),
        )

    for transaction in pages(API + "/transactions?page[size]=100"):
        a, r = transaction["attributes"], transaction["relationships"]
        foreign = a["foreignAmount"]
        database.execute(
            "insert into transactions values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            (
                transaction["id"],
                a["createdAt"],
                a["createdAt"][:10],
                a["settledAt"],
                names.get(related(r, "account")),
                a["status"],
                a["description"],
                a["message"],
                a["rawText"],
                dollars(a["amount"]),
                dollars(foreign),
                foreign and foreign["currencyCode"],
                related(r, "category"),
                related(r, "parentCategory"),
                ";".join(tag["id"] for tag in r["tags"]["data"]) or None,
                names.get(related(r, "transferAccount")),
            ),
        )

    database.execute("insert into synced values (?)", (datetime.now(timezone.utc).isoformat(timespec="seconds"),))
    database.commit()
    database.close()
    os.replace(partial, DATABASE)


main()
