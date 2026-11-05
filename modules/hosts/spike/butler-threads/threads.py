"""Butler's Discord threads, as names, kinds, times and states alone, for the life explorer's Threads section.

Reads the daemon's threads.db read-only and writes a JSON snapshot. No message text, prompt, reply or error
ever leaves the database: only each thread's title, which kind of turn started it, which scheduled job ran it,
its times, its turn count and spend, and whether it is running, waiting, idle, archived, failed or cleared.
"""

import json
import os
import re
import sqlite3
import sys
import time

LIMIT = 500
JOB = re.compile(r"^(?:cron|schedule)-(.+)$")
EPOCH = re.compile(r"-\d{9,}$")
SNOWFLAKE = re.compile(r"^\d{1,25}$")


def kind_of(thread, first_author):
    author = first_author or ""
    if author.startswith(("cron-", "schedule-")):
        return "scheduled"
    if author.startswith("board-"):
        return "board"
    if author.startswith("delegate-voice") or (thread["tainted"] or 0) & 2:
        return "voice"
    if thread["guild_id"] is None:
        return "dm"
    return "conversation"


def job_of(first_author):
    match = JOB.match(first_author or "")
    if not match:
        return None
    if first_author.startswith("schedule-"):
        return f"schedule #{match.group(1)}"
    name = EPOCH.sub("", match.group(1))
    return name[4:] if name.startswith("job-") else name


def status_of(thread, kind, last):
    if last and last["state"] in ("running", "delivering"):
        return "running"
    if last and last["state"] in ("queued", "seen"):
        return "waiting"
    if thread["state"] == "archived":
        # A quiet scheduled run that had nothing to say is archived with an answer that posted nothing, its thread deleted.
        if kind == "scheduled" and last and last["state"] == "done" and (last["reply_message_ids"] or "[]") == "[]":
            return "cleared"
        return "archived"
    if last and last["state"] == "failed":
        return "failed"
    return "idle"


def link_of(thread):
    ident = thread["thread_id"]
    if not SNOWFLAKE.match(ident or ""):
        return None
    guild = thread["guild_id"]
    if guild is not None and not SNOWFLAKE.match(guild):
        return None
    return f"https://discord.com/channels/{guild or '@me'}/{ident}"


def seconds(ms):
    return int(ms // 1000) if isinstance(ms, (int, float)) and ms > 0 else None


def snapshot(database, now=None):
    now = int(now or time.time())
    connection = sqlite3.connect(f"file:{database}?mode=ro", uri=True)
    connection.row_factory = sqlite3.Row
    try:
        threads = connection.execute(
            "SELECT thread_id, guild_id, title, state, tainted, created_at, last_active_at FROM threads ORDER BY last_active_at DESC LIMIT ?",
            (LIMIT,),
        ).fetchall()
        out = []
        for thread in threads:
            ident = thread["thread_id"]
            first = connection.execute("SELECT author_id FROM turns WHERE thread_id = ? ORDER BY id LIMIT 1", (ident,)).fetchone()
            last = connection.execute("SELECT state, reply_message_ids, updated_at FROM turns WHERE thread_id = ? ORDER BY id DESC LIMIT 1", (ident,)).fetchone()
            totals = connection.execute("SELECT COUNT(*) AS turns, SUM(cost_usd) AS cost FROM turns WHERE thread_id = ?", (ident,)).fetchone()
            author = first["author_id"] if first else None
            kind = kind_of(thread, author)
            title = (thread["title"] or "").strip()[:100] or ("Direct messages" if kind == "dm" else None)
            last_active = max(filter(None, [seconds(thread["last_active_at"]), seconds(last["updated_at"]) if last else None]), default=None)
            out.append({
                "id": ident,
                "title": title,
                "kind": kind,
                "job": job_of(author),
                "status": status_of(thread, kind, last),
                "created": seconds(thread["created_at"]),
                "last": last_active,
                "turns": totals["turns"] or 0,
                "cost": round(totals["cost"], 2) if totals["cost"] else 0,
                "private": bool((thread["tainted"] or 0) & 1),
                "link": link_of(thread),
            })
    finally:
        connection.close()
    out.sort(key=lambda entry: entry["last"] or 0, reverse=True)
    day = now - 24 * 3600
    counts = {
        "open": sum(entry["status"] in ("running", "waiting", "idle", "failed") for entry in out),
        "running": sum(entry["status"] in ("running", "waiting") for entry in out),
        "scheduled_today": sum(entry["kind"] == "scheduled" and (entry["created"] or 0) >= day for entry in out),
        "cleared_today": sum(entry["status"] == "cleared" and (entry["last"] or 0) >= day for entry in out),
    }
    return {"generated": now, "counts": counts, "threads": out}


def write(path, data):
    temporary = f"{path}.tmp"
    with open(temporary, "w", encoding="utf-8") as handle:
        json.dump(data, handle, ensure_ascii=False)
    os.chmod(temporary, 0o640)
    os.replace(temporary, path)


def main(argv):
    database, output = argv[1], argv[2]
    if not os.path.exists(database):
        write(output, {"generated": int(time.time()), "counts": {}, "threads": [], "missing": True})
        return 0
    write(output, snapshot(database))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
