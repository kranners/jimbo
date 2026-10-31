import json
import sqlite3
from datetime import datetime, timezone

DATABASE = "@database@"

SCHEMA = """
CREATE TABLE IF NOT EXISTS records (
  id INTEGER PRIMARY KEY,
  source TEXT NOT NULL,
  uid TEXT NOT NULL,
  kind TEXT NOT NULL,
  ts TEXT NOT NULL,
  day TEXT NOT NULL,
  title TEXT NOT NULL DEFAULT '',
  body TEXT NOT NULL DEFAULT '',
  place TEXT NOT NULL DEFAULT '',
  amount REAL,
  currency TEXT,
  latitude REAL,
  longitude REAL,
  extra TEXT NOT NULL DEFAULT '{}',
  UNIQUE (source, uid)
);
CREATE INDEX IF NOT EXISTS records_day ON records (day, source);
CREATE VIRTUAL TABLE IF NOT EXISTS records_fts USING fts5(
  title, body, place, content='records', content_rowid='id', tokenize='porter unicode61'
);
CREATE TRIGGER IF NOT EXISTS records_ai AFTER INSERT ON records BEGIN
  INSERT INTO records_fts (rowid, title, body, place) VALUES (new.id, new.title, new.body, new.place);
END;
CREATE TRIGGER IF NOT EXISTS records_ad AFTER DELETE ON records BEGIN
  INSERT INTO records_fts (records_fts, rowid, title, body, place) VALUES ('delete', old.id, old.title, old.body, old.place);
END;
CREATE TRIGGER IF NOT EXISTS records_au AFTER UPDATE ON records BEGIN
  INSERT INTO records_fts (records_fts, rowid, title, body, place) VALUES ('delete', old.id, old.title, old.body, old.place);
  INSERT INTO records_fts (rowid, title, body, place) VALUES (new.id, new.title, new.body, new.place);
END;
CREATE TABLE IF NOT EXISTS ingests (source TEXT PRIMARY KEY, at TEXT NOT NULL, added INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS spend (at TEXT NOT NULL, purpose TEXT NOT NULL, usd REAL NOT NULL);
CREATE TABLE IF NOT EXISTS state (key TEXT PRIMARY KEY, value TEXT NOT NULL);
"""


def open_for_writing():
    connection = sqlite3.connect(DATABASE, timeout=120)
    connection.execute("PRAGMA journal_mode=DELETE")
    connection.executescript(SCHEMA)
    return connection


def utc(moment):
    if moment.tzinfo is None:
        moment = moment.replace(tzinfo=timezone.utc)
    return moment.astimezone(timezone.utc)


def parse_time(text):
    return utc(datetime.fromisoformat(text.replace("Z", "+00:00")))


def upsert(connection, source, uid, kind, moment, title="", body="", place="", amount=None, currency=None, latitude=None, longitude=None, extra=None):
    moment = utc(moment)
    connection.execute(
        """
        INSERT INTO records (source, uid, kind, ts, day, title, body, place, amount, currency, latitude, longitude, extra)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT (source, uid) DO UPDATE SET
          kind = excluded.kind, ts = excluded.ts, day = excluded.day, title = excluded.title, body = excluded.body,
          place = excluded.place, amount = excluded.amount, currency = excluded.currency,
          latitude = excluded.latitude, longitude = excluded.longitude, extra = excluded.extra
        """,
        (
            source,
            uid,
            kind,
            moment.isoformat(timespec="seconds"),
            moment.astimezone().date().isoformat(),
            title or "",
            body or "",
            place or "",
            amount,
            currency,
            latitude,
            longitude,
            json.dumps(extra or {}, ensure_ascii=False),
        ),
    )


def record_ingest(connection, source, added):
    connection.execute(
        "INSERT INTO ingests (source, at, added) VALUES (?, ?, ?) ON CONFLICT (source) DO UPDATE SET at = excluded.at, added = excluded.added",
        (source, datetime.now(timezone.utc).isoformat(timespec="seconds"), added),
    )
    connection.commit()


def month_spend(connection):
    month = datetime.now(timezone.utc).strftime("%Y-%m")
    return connection.execute("SELECT COALESCE(SUM(usd), 0) FROM spend WHERE substr(at, 1, 7) = ?", (month,)).fetchone()[0]
