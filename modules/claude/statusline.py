"""Claude Code status line.

Reads the status line JSON on stdin and prints one line:

  Opus 5  jimbo:main  session 1.2M $4.31  turn 210k $0.68  today 8.4M $22.10  [###---] 61% left

Session cost comes from Claude Code itself. Token counts and the daily cost are
summed from the JSONL transcripts under ~/.claude/projects, priced with the same
table Claude Code uses. The turn figure covers the most recent prompt and every
request it triggered, so per prompt cost can be watched climbing as the context
grows. The usage bar is the five hour rate limit window.
"""

import json
import os
import subprocess
import sys
import time
from datetime import datetime, timezone

# Dollars per million tokens, lifted from the Claude Code model catalog.
TIERS = {
    "tier_2_10": (2, 10, 2.5, 4, 0.2),
    "tier_3_15": (3, 15, 3.75, 6, 0.3),
    "tier_5_25": (5, 25, 6.25, 10, 0.5),
    "tier_10_50": (10, 50, 12.5, 20, 1),
    "tier_10_50_cache_read_0_25": (10, 50, 12.5, 20, 0.25),
    "tier_15_75": (15, 75, 18.75, 30, 1.5),
    "haiku_35": (0.8, 4, 1, 1.6, 0.08),
    "haiku_45": (1, 5, 1.25, 2, 0.1),
}

MODEL_TIERS = {
    "claude-3-5-haiku": "haiku_35",
    "claude-3-5-sonnet": "tier_3_15",
    "claude-3-7-sonnet": "tier_3_15",
    "claude-fable-5": "tier_10_50",
    "claude-fable-5-1": "tier_10_50_cache_read_0_25",
    "claude-haiku-4-5": "haiku_45",
    "claude-mythos-5": "tier_10_50",
    "claude-mythos-5-1": "tier_10_50_cache_read_0_25",
    "claude-opus-4-0": "tier_15_75",
    "claude-opus-4-1": "tier_15_75",
    "claude-opus-4-5": "tier_5_25",
    "claude-opus-4-6": "tier_5_25",
    "claude-opus-4-7": "tier_5_25",
    "claude-opus-4-8": "tier_5_25",
    "claude-opus-5": "tier_5_25",
    "claude-sonnet-4-0": "tier_3_15",
    "claude-sonnet-4-5": "tier_3_15",
    "claude-sonnet-4-6": "tier_3_15",
    "claude-sonnet-5": "tier_2_10",
}

# Fast mode is billed at the undiscounted tier.
FAST_TIERS = {
    "claude-opus-4-6": "tier_15_75",
    "claude-opus-4-7": "tier_15_75",
    "claude-opus-4-8": "tier_10_50",
    "claude-opus-5": "tier_10_50",
}

WEB_SEARCH_USD = 0.01
US_GEO_MULTIPLIER = 1.1

DIM = "\033[2m"
BOLD = "\033[1m"
RESET = "\033[0m"
GREEN = "\033[32m"
YELLOW = "\033[33m"
RED = "\033[31m"


def normalise_model(model):
    """Strip provider prefixes and date suffixes: bedrock/claude-opus-5-20260101."""
    name = model.rsplit("/", 1)[-1].lower()
    name = name.split(":", 1)[0]
    parts = name.split("-")
    if parts and len(parts[-1]) == 8 and parts[-1].isdigit():
        parts = parts[:-1]
    return "-".join(parts)


def price(model, usage):
    name = normalise_model(model)
    tier = None
    if usage.get("speed") == "fast":
        tier = FAST_TIERS.get(name)
    tier = tier or MODEL_TIERS.get(name) or "tier_5_25"
    inp, out, write_5m, write_1h, read = TIERS[tier]

    created = usage.get("cache_creation_input_tokens") or 0
    long_lived = min((usage.get("cache_creation") or {}).get("ephemeral_1h_input_tokens") or 0, created)
    write_cost = (long_lived * write_1h + (created - long_lived) * write_5m) / 1e6

    cost = (
        (usage.get("input_tokens") or 0) * inp / 1e6
        + (usage.get("output_tokens") or 0) * out / 1e6
        + (usage.get("cache_read_input_tokens") or 0) * read / 1e6
        + write_cost
    )
    if usage.get("inference_geo") == "us":
        cost *= US_GEO_MULTIPLIER
    searches = (usage.get("server_tool_use") or {}).get("web_search_requests") or 0
    return cost + searches * WEB_SEARCH_USD


def tokens(usage):
    return sum(
        usage.get(key) or 0
        for key in (
            "input_tokens",
            "output_tokens",
            "cache_read_input_tokens",
            "cache_creation_input_tokens",
        )
    )


def scan(paths, seen, on_date=None, since=None):
    """Sum tokens and cost over transcript files, deduplicating repeated blocks.

    ``since`` narrows the sum to entries written at or after that moment.
    """
    total_tokens = 0.0
    total_cost = 0.0
    for path in paths:
        try:
            handle = open(path, "rb")
        except OSError:
            continue
        with handle:
            for raw in handle:
                if b'"usage"' not in raw:
                    continue
                try:
                    entry = json.loads(raw)
                except ValueError:
                    continue
                if entry.get("type") != "assistant":
                    continue
                message = entry.get("message") or {}
                usage = message.get("usage")
                model = message.get("model")
                if not usage or not model or model.startswith("<"):
                    continue
                key = (entry.get("requestId"), message.get("id"))
                if key in seen:
                    continue
                seen.add(key)
                if on_date and local_date(entry.get("timestamp")) != on_date:
                    continue
                if since:
                    stamp = parse_time(entry.get("timestamp"))
                    if stamp is None or stamp < since:
                        continue
                total_tokens += tokens(usage)
                total_cost += price(model, usage)
    return total_tokens, total_cost


def parse_time(stamp):
    if not stamp:
        return None
    try:
        parsed = datetime.fromisoformat(stamp.replace("Z", "+00:00"))
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed


def local_date(stamp):
    parsed = parse_time(stamp)
    return parsed.astimezone().date() if parsed else None


def session_files(transcript):
    """The session transcript plus any subagent transcripts beside it."""
    if not transcript or not os.path.exists(transcript):
        return []
    files = [transcript]
    subagents = os.path.join(transcript[: -len(".jsonl")], "subagents")
    if os.path.isdir(subagents):
        files += [os.path.join(subagents, name) for name in os.listdir(subagents) if name.endswith(".jsonl")]
    return files


def last_prompt_time(transcript):
    """When the newest user prompt landed, ignoring tool results and injections."""
    if not transcript or not os.path.exists(transcript):
        return None
    try:
        handle = open(transcript, "rb")
    except OSError:
        return None
    latest = None
    with handle:
        for raw in handle:
            if b'"user"' not in raw:
                continue
            try:
                entry = json.loads(raw)
            except ValueError:
                continue
            if entry.get("type") != "user":
                continue
            if entry.get("isMeta") or entry.get("isSidechain") or entry.get("isCompactSummary"):
                continue
            content = (entry.get("message") or {}).get("content")
            if isinstance(content, list) and all(
                isinstance(block, dict) and block.get("type") == "tool_result" for block in content
            ):
                continue
            stamp = parse_time(entry.get("timestamp"))
            if stamp and (latest is None or stamp > latest):
                latest = stamp
    return latest


def todays_files(midnight):
    root = os.path.expanduser("~/.claude/projects")
    found = []
    for dirpath, _, names in os.walk(root):
        for name in names:
            if not name.endswith(".jsonl"):
                continue
            path = os.path.join(dirpath, name)
            try:
                if os.stat(path).st_mtime >= midnight:
                    found.append(path)
            except OSError:
                pass
    return found


def git(cwd, *args):
    try:
        out = subprocess.run(
            ("git", "-C", cwd) + args,
            capture_output=True,
            text=True,
            timeout=2,
        )
    except (OSError, subprocess.SubprocessError):
        return ""
    return out.stdout.strip() if out.returncode == 0 else ""


def repo_name(status, cwd):
    """Name the repository, not the worktree directory it is checked out into."""
    named = ((status.get("workspace") or {}).get("repo") or {}).get("name")
    if named:
        return named
    common = git(cwd, "rev-parse", "--path-format=absolute", "--git-common-dir")
    if common:
        return os.path.basename(os.path.dirname(common.rstrip("/")))
    return os.path.basename(cwd)


def human(count):
    if count >= 1e6:
        return "%.1fM" % (count / 1e6)
    if count >= 1e3:
        return "%.0fk" % (count / 1e3)
    return "%d" % count


def bar(remaining, width=10):
    filled = max(0, min(width, int(round(remaining * width))))
    colour = GREEN if remaining > 0.5 else YELLOW if remaining > 0.2 else RED
    return colour + "#" * filled + DIM + "-" * (width - filled) + RESET


def usage_left(status):
    five_hour = (status.get("rate_limits") or {}).get("five_hour")
    if not five_hour:
        return None
    remaining = max(0.0, 1.0 - (five_hour.get("used_percentage") or 0) / 100.0)
    resets = five_hour.get("resets_at")
    label = "%s %d%% left" % (bar(remaining), round(remaining * 100))
    if resets:
        minutes = max(0, int((resets - time.time()) // 60))
        label += DIM + " resets in %dh%02dm" % (minutes // 60, minutes % 60) + RESET
    return label


def main():
    status = json.load(sys.stdin)
    cwd = (status.get("workspace") or {}).get("current_dir") or status.get("cwd") or os.getcwd()

    model = (status.get("model") or {}).get("display_name") or "?"
    branch = git(cwd, "branch", "--show-current") or git(cwd, "rev-parse", "--short", "HEAD") or "-"

    transcript = status.get("transcript_path")
    files = session_files(transcript)
    session_tokens, _ = scan(files, set())
    session_cost = (status.get("cost") or {}).get("total_cost_usd") or 0.0

    turn_start = last_prompt_time(transcript)
    turn_tokens, turn_cost = scan(files, set(), since=turn_start) if turn_start else (0.0, 0.0)

    midnight = datetime.now().astimezone().replace(hour=0, minute=0, second=0, microsecond=0)
    day_tokens, day_cost = scan(todays_files(midnight.timestamp()), set(), on_date=midnight.date())

    parts = [
        BOLD + model + RESET,
        "%s%s:%s%s" % (repo_name(status, cwd), DIM, RESET, branch),
        "session %s %s$%.2f%s" % (human(session_tokens), DIM, session_cost, RESET),
        "turn %s %s$%.2f%s" % (human(turn_tokens), DIM, turn_cost, RESET),
        "today %s %s$%.2f%s" % (human(day_tokens), DIM, day_cost, RESET),
    ]
    left = usage_left(status)
    if left:
        parts.append(left)
    print((DIM + "  ·  " + RESET).join(parts))


if __name__ == "__main__":
    try:
        main()
    except Exception:
        print("")
