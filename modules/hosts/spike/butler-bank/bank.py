import csv
import os
import pwd
import sqlite3
import sys
import time
from pathlib import Path

DATABASE = Path(pwd.getpwuid(os.getuid()).pw_dir) / "bank" / "up.sqlite"
MAX_ROWS = 200
MAX_SECONDS = 20
READING = {sqlite3.SQLITE_SELECT, sqlite3.SQLITE_READ, sqlite3.SQLITE_FUNCTION, sqlite3.SQLITE_RECURSIVE}

USAGE = """usage: bank schema
       bank sql <select statement>"""


def usage():
    print(USAGE, file=sys.stderr)
    sys.exit(2)


def connect():
    if not DATABASE.exists():
        print("bank: there is no copy of Aaron's transactions yet; butler-bank-sync makes one nightly once the Up token is in /var/lib/secrets/butler-up-token", file=sys.stderr)
        sys.exit(75)
    database = sqlite3.connect(f"file:{DATABASE}?mode=ro", uri=True)
    database.set_authorizer(lambda action, *_: sqlite3.SQLITE_OK if action in READING else sqlite3.SQLITE_DENY)
    deadline = time.monotonic() + MAX_SECONDS
    database.set_progress_handler(lambda: time.monotonic() > deadline, 10000)
    return database


def schema(database):
    for (sql,) in database.execute("select sql from sqlite_master where type = 'table'"):
        print(sql + ";")
    (synced,) = database.execute("select at from synced").fetchone()
    (count, first, last) = database.execute("select count(*), min(created_on), max(created_on) from transactions").fetchone()
    print(f"-- {count} transactions from {first} to {last}, synced {synced}")


def query(database, statement):
    try:
        cursor = database.execute(statement)
        rows = cursor.fetchmany(MAX_ROWS + 1)
    except sqlite3.Error as error:
        print(f"bank: {error}", file=sys.stderr)
        sys.exit(1)
    out = csv.writer(sys.stdout)
    out.writerow(column[0] for column in cursor.description or [])
    out.writerows(rows[:MAX_ROWS])
    if len(rows) > MAX_ROWS:
        print(f"-- cut off at {MAX_ROWS} rows; aggregate or add a limit")


match sys.argv[1:]:
    case ["schema"]:
        schema(connect())
    case ["sql", *words] if words:
        query(connect(), " ".join(words))
    case _:
        usage()
