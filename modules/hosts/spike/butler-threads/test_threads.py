"""threads.py over a fixture threads.db, checking kinds, states and that no message text gets out."""

import importlib.util
import json
import os
import sqlite3
import sys
import tempfile

spec = importlib.util.spec_from_file_location("threads", sys.argv[1])
threads = importlib.util.module_from_spec(spec)
spec.loader.exec_module(threads)

directory = tempfile.mkdtemp()
database = os.path.join(directory, "threads.db")
db = sqlite3.connect(database)
db.executescript("""
CREATE TABLE threads (thread_id TEXT PRIMARY KEY, channel_id TEXT, root_message_id TEXT, guild_id TEXT, cc_session_id TEXT, cwd TEXT,
  title TEXT, state TEXT, model TEXT, effort TEXT, permission_mode TEXT, header_message_id TEXT, worktree_path TEXT, tainted INTEGER,
  created_at INTEGER, last_active_at INTEGER);
CREATE TABLE turns (id INTEGER PRIMARY KEY AUTOINCREMENT, thread_id TEXT, inbound_message_id TEXT, author_id TEXT, content TEXT, state TEXT,
  status_message_id TEXT, reply_message_ids TEXT, error TEXT, attempts INTEGER, cost_usd REAL, input_tokens INTEGER, output_tokens INTEGER,
  duration_ms INTEGER, created_at INTEGER, updated_at INTEGER);
""")
T = 1_800_000_000_000
rows = [
    ("1001", "9", "Weekly plan chat", "open", 0, T, T + 5000, [("193903125994799114", "SECRET-PROMPT plan my week", "done", "[\"1\"]", 0.12)]),
    ("1002", "9", "didi-export-check, Wed 4 Nov", "archived", 0, T + 10, T + 6000, [("cron-job-didi-export-check-1762230000", "SECRET-PROMPT check exports", "done", "[]", 0.03)]),
    ("1003", "9", "Morning brief, Wed 4 Nov", "open", 1, T + 20, T + 7000, [("cron-morning-brief", "SECRET-PROMPT brief", "running", None, None)]),
    ("1004", None, None, "open", 1, T + 30, T + 8000, [("193903125994799114", "SECRET-PROMPT my blood test", "failed", None, None)]),
    ("1005", "9", "Board: tidy", "archived", 2, T + 40, T + 9000, [("board-a/b", "SECRET-PROMPT tidy", "done", "[\"2\"]", None)]),
]
for ident, guild, title, state, tainted, created, last, turns in rows:
    db.execute("INSERT INTO threads VALUES (?, ?, NULL, ?, NULL, '/', ?, ?, NULL, NULL, NULL, NULL, NULL, ?, ?, ?)", (ident, ident, guild, title, state, tainted, created, last))
    for n, (author, content, turn_state, replies, cost) in enumerate(turns):
        db.execute("INSERT INTO turns (thread_id, inbound_message_id, author_id, content, state, reply_message_ids, error, attempts, cost_usd, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, 'SECRET-ERROR', 0, ?, ?, ?)",
                   (ident, f"{ident}-{n}", author, content, turn_state, replies, cost, created, last))
db.commit()
db.close()

data = threads.snapshot(database, now=T // 1000 + 3600)
text = json.dumps(data)
assert "SECRET" not in text, text
by = {entry["id"]: entry for entry in data["threads"]}
assert [entry["id"] for entry in data["threads"]] == ["1005", "1004", "1003", "1002", "1001"], data
assert by["1001"]["kind"] == "conversation" and by["1001"]["status"] == "idle" and by["1001"]["cost"] == 0.12
assert by["1001"]["link"] == "https://discord.com/channels/9/1001"
assert by["1002"]["kind"] == "scheduled" and by["1002"]["job"] == "didi-export-check" and by["1002"]["status"] == "cleared", by["1002"]
assert by["1003"]["job"] == "morning-brief" and by["1003"]["status"] == "running" and by["1003"]["private"]
assert by["1004"]["kind"] == "dm" and by["1004"]["title"] == "Direct messages" and by["1004"]["status"] == "failed"
assert by["1004"]["link"] == "https://discord.com/channels/@me/1004"
assert by["1005"]["kind"] == "board"
assert by["1005"]["status"] == "archived"
assert data["counts"] == {"open": 3, "running": 1, "scheduled_today": 2, "cleared_today": 1}, data["counts"]

output = os.path.join(directory, "out.json")
assert threads.main(["threads", os.path.join(directory, "missing.db"), output]) == 0
assert json.load(open(output))["missing"] is True
print("ok")
