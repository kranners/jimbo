"""Claude Code status line.

Reads the status line JSON on stdin and prints three lines:

  Opus 5.5  ·  jimbo:main  ·  jimbo-50
  turn 210k $0.68  ·  session 1.2M $4.31  ·  today 8.4M $22.10  ·  week 51M $310.20
  context ########-- 84% left  ·  session ######---- 61% left 2h10m  ·  week ####------ 43% left 1d3h  ·  Fable ...

Session cost comes from Claude Code itself. Token counts and the other costs are
summed from the JSONL transcripts under ~/.claude/projects, priced with the same
table Claude Code uses. The turn figure covers the most recent prompt and every
request it triggered, so per prompt cost can be watched climbing as the context
grows. The week figure runs from the start of the weekly limit's window.

With CLAUDE_STATUSLINE_PLAIN=1 it drops the first line, the bars and the colours,
for the footer discord-threads posts under each reply.

Context is scaled to the point autocompaction fires rather than to the raw
window. Plan limits come from the endpoint behind /usage, shared between
sessions through a short lived cache, because the status line payload only
carries the five hour and weekly windows as of this session's own last request.
"""

import json
import os
import subprocess
import sys
import time
import urllib.request
from datetime import datetime, timedelta, timezone

# Dollars per million tokens, lifted from the Claude Code model catalog.
TIERS = {
    "tier_2_10": (2, 10, 2.5, 4, 0.2),
    "tier_3_15": (3, 15, 3.75, 6, 0.3),
    "tier_4_20_cache_read_0_20": (4, 20, 5, 8, 0.2),
    "tier_5_25": (5, 25, 6.25, 10, 0.5),
    "tier_8_40_cache_read_0_40": (8, 40, 10, 16, 0.4),
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
    "claude-opus-5-5": "tier_4_20_cache_read_0_20",
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
    "claude-opus-5-5": "tier_8_40_cache_read_0_40",
}

WEB_SEARCH_USD = 0.01
US_GEO_MULTIPLIER = 1.1

# Context windows are absent from the status line payload, so this is a table
# like the tiers above; /context reports the live figure. The default is
# deliberately low. A window guessed too large hides autocompaction coming, and
# window_for corrects itself upwards once a request proves the table stale.
DEFAULT_WINDOW = 200_000
MAX_WINDOW = 1_000_000
MODEL_WINDOWS = {
    "claude-opus-5": MAX_WINDOW,
    "claude-opus-5-5": MAX_WINDOW,
    "claude-fable-5-1": MAX_WINDOW,
}

# Autocompaction fires this far short of the window. Read off /context on a 1m
# window; the figure on smaller windows has not been checked.
AUTOCOMPACT_BUFFER = 33_000

USAGE_URL = "https://api.anthropic.com/api/oauth/usage"
USAGE_CACHE = os.path.expanduser("~/.cache/claude-statusline/usage.json")
USAGE_TTL = 60

PLAIN = os.environ.get("CLAUDE_STATUSLINE_PLAIN") == "1"

DIM, BOLD, RESET, GREEN, YELLOW, RED = (
    ("",) * 6 if PLAIN else ("\033[2m", "\033[1m", "\033[0m", "\033[32m", "\033[33m", "\033[31m")
)


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


def scan(paths, starts):
    """Sum tokens and cost over transcript files once per start, in one read.

    Each sum covers the entries written at or after its start; a start of None
    covers them all. Repeated blocks are counted once.
    """
    totals = [[0.0, 0.0] for _ in starts]
    seen = set()
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
                stamp = parse_time(entry.get("timestamp"))
                for total, start in zip(totals, starts):
                    if start is None or (stamp is not None and stamp >= start):
                        total[0] += tokens(usage)
                        total[1] += price(model, usage)
    return totals


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


def context_use(transcript):
    """Context size and model at the newest request, skipping subagent turns."""
    if not transcript or not os.path.exists(transcript):
        return None
    try:
        handle = open(transcript, "rb")
    except OSError:
        return None
    last = model = None
    with handle:
        for raw in handle:
            if b'"usage"' not in raw:
                continue
            try:
                entry = json.loads(raw)
            except ValueError:
                continue
            if entry.get("type") != "assistant" or entry.get("isSidechain"):
                continue
            message = entry.get("message") or {}
            usage = message.get("usage")
            name = message.get("model")
            if not usage or not name or name.startswith("<"):
                continue
            total = sum(
                usage.get(key) or 0
                for key in ("input_tokens", "cache_read_input_tokens", "cache_creation_input_tokens")
            )
            if total:
                last, model = total, name
    return (last, model) if last else None


def window_for(model, used):
    window = MODEL_WINDOWS.get(normalise_model(model), DEFAULT_WINDOW)
    # A request larger than the table allows means the table is stale, not that
    # autocompaction failed to fire.
    if used >= window - AUTOCOMPACT_BUFFER:
        window = max(window, MAX_WINDOW)
    return window


def files_since(start):
    root = os.path.expanduser("~/.claude/projects")
    found = []
    for dirpath, _, names in os.walk(root):
        for name in names:
            if not name.endswith(".jsonl"):
                continue
            path = os.path.join(dirpath, name)
            try:
                if os.stat(path).st_mtime >= start:
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
    if count >= 1e9:
        return "%.1fB" % (count / 1e9)
    if count >= 1e6:
        return "%.1fM" % (count / 1e6)
    if count >= 1e3:
        return "%.0fk" % (count / 1e3)
    return "%d" % count


def bar(remaining, width=10):
    filled = max(0, min(width, int(round(remaining * width))))
    return colour_for(remaining) + "#" * filled + DIM + "-" * (width - filled) + RESET


def colour_for(remaining):
    return GREEN if remaining > 0.5 else YELLOW if remaining > 0.2 else RED


def remaining_label(label, remaining, resets=None):
    gauge = "" if PLAIN else bar(remaining) + " "
    text = "%s %s%s%d%% left%s" % (label, gauge, colour_for(remaining), round(remaining * 100), RESET)
    if resets:
        text += DIM + " " + until(resets) + RESET
    return text


def context_left(transcript):
    seen = context_use(transcript)
    if not seen:
        return None
    used, model = seen
    limit = window_for(model, used) - AUTOCOMPACT_BUFFER
    return remaining_label("context", max(0.0, 1.0 - used / float(limit)))


def oauth_token():
    if sys.platform == "darwin":
        raw = subprocess.run(
            ("security", "find-generic-password", "-s", "Claude Code-credentials", "-w"),
            capture_output=True,
            text=True,
            timeout=2,
        ).stdout
    else:
        with open(os.path.expanduser("~/.claude/.credentials.json")) as handle:
            raw = handle.read()
    return json.loads(raw)["claudeAiOauth"]["accessToken"]


def fetch_usage():
    request = urllib.request.Request(
        USAGE_URL,
        headers={
            "Authorization": "Bearer " + oauth_token(),
            "anthropic-beta": "oauth-2025-04-20",
        },
    )
    with urllib.request.urlopen(request, timeout=2) as response:
        return json.load(response)


def account_usage():
    """The /usage reading, fetched at most once a minute across every session."""
    try:
        if time.time() - os.stat(USAGE_CACHE).st_mtime < USAGE_TTL:
            with open(USAGE_CACHE) as handle:
                return json.load(handle)
    except (OSError, ValueError):
        pass
    try:
        usage = fetch_usage()
    except Exception:
        return None
    os.makedirs(os.path.dirname(USAGE_CACHE), exist_ok=True)
    partial = "%s.%d" % (USAGE_CACHE, os.getpid())
    with open(partial, "w") as handle:
        json.dump(usage, handle)
    os.replace(partial, USAGE_CACHE)
    return usage


def epoch(resets):
    if isinstance(resets, (int, float)):
        return resets
    parsed = parse_time(resets)
    return parsed.timestamp() if parsed else None


def limits(status):
    """(label, percent used, reset epoch) for the five hour session window, then the weekly ones."""
    usage = account_usage()
    if usage and usage.get("limits"):
        found = []
        for row in usage["limits"]:
            kind = row.get("kind")
            model = ((row.get("scope") or {}).get("model") or {}).get("display_name")
            if kind == "session":
                label = "session"
            elif kind == "weekly_all":
                label = "week"
            elif kind == "weekly_scoped" and model:
                label = model
            else:
                continue
            found.append((label, row.get("percent") or 0, epoch(row.get("resets_at"))))
        return found
    windows = status.get("rate_limits") or {}
    return [
        (label, window.get("used_percentage") or 0, epoch(window.get("resets_at")))
        for label, window in (("session", windows.get("five_hour")), ("week", windows.get("seven_day")))
        if window
    ]


def until(resets):
    minutes = max(0, int((resets - time.time()) // 60))
    if minutes >= 24 * 60:
        return "%dd%dh" % (minutes // (24 * 60), minutes // 60 % 24)
    return "%dh%02dm" % (minutes // 60, minutes % 60)


def week_start(plan_limits):
    resets = next((resets for label, _, resets in plan_limits if label == "week" and resets), None)
    if resets:
        return datetime.fromtimestamp(resets, timezone.utc) - timedelta(days=7)
    return datetime.now(timezone.utc) - timedelta(days=7)


def spend(label, totals):
    count, cost = totals
    return "%s %s %s$%.2f%s" % (label, human(count), DIM, cost, RESET)


def main():
    status = json.load(sys.stdin)
    cwd = (status.get("workspace") or {}).get("current_dir") or status.get("cwd") or os.getcwd()
    separator = DIM + "  ·  " + RESET

    model = (status.get("model") or {}).get("display_name") or "?"
    branch = git(cwd, "branch", "--show-current") or git(cwd, "rev-parse", "--short", "HEAD") or "-"
    header = [BOLD + model + RESET, "%s%s:%s%s" % (repo_name(status, cwd), DIM, RESET, branch)]
    if status.get("session_name"):
        header.append(status["session_name"])
    if not PLAIN:
        print(separator.join(header))

    transcript = status.get("transcript_path")
    files = session_files(transcript)
    turn_start = last_prompt_time(transcript)
    session, turn = scan(files, (None, turn_start or datetime.max.replace(tzinfo=timezone.utc)))
    session[1] = (status.get("cost") or {}).get("total_cost_usd") or 0.0

    plan_limits = limits(status)
    midnight = datetime.now().astimezone().replace(hour=0, minute=0, second=0, microsecond=0)
    week = week_start(plan_limits)
    today, this_week = scan(files_since(min(midnight, week).timestamp()), (midnight, week))
    print(
        separator.join(
            [spend("turn", turn), spend("session", session), spend("today", today), spend("week", this_week)]
        )
    )

    remaining = [
        remaining_label(label, max(0.0, 1.0 - used / 100.0), resets) for label, used, resets in plan_limits
    ]
    context = context_left(transcript)
    if context:
        remaining.insert(0, context)
    if remaining:
        print(separator.join(remaining))


if __name__ == "__main__":
    try:
        main()
    except Exception:
        print("")
