# Butler's read-only view of Aaron's work Slack workspace.
#
# Every call is a GET of a conversations, users, search, files or auth method, or of a file's own
# private URL on files.slack.com, so it can never post, react, edit or mark anything read.
# A message is printed whole: its rich text blocks, its text, any shared message or link unfurl it
# carries and, with files:read, the text of its snippets, text files and canvases, so nothing is
# cut short at Slack's "see more"; only the daemon's own output limit bounds a run, and the tool
# stops before it, naming what it left out.
import html
import json
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime

CREDENTIAL = "@credential@"
API = "https://slack.com/api/"
# The token is only ever sent to Slack's own hosts.
FILE_HOSTS = {"files.slack.com", "slack-files.com"}
# What `slack scopes` checks: the scopes every verb needs, then those that make it fuller.
NEEDED = [
    "channels:history", "channels:read", "groups:history", "groups:read", "im:history", "im:read",
    "mpim:history", "mpim:read", "search:read", "users:read",
]
HELPFUL = {
    "files:read": "the text of snippets, text files and canvases shared in a message, and files shared from other workspaces",
    "canvases:read": "a channel's or DM's own canvas (its tab), which no message links",
    "pins:read": "a channel's pinned messages",
    "bookmarks:read": "a channel's bookmarks bar",
    "reactions:read": "who reacted to a message",
    "usergroups:read": "the names of @groups mentioned in a message",
    "team:read": "the workspace's own name and domain",
}
# The daemon cuts a command's output at 50,000 characters, so a run stops a little short of it.
BUDGET = 45000
FILE_TEXT = 20000
FILE_BYTES = 512 * 1024
MAX_PAGES = 50
TEXT_TYPES = {"text", "markdown", "plaintext", "csv", "tsv", "json", "yaml", "xml", "html", "javascript", "typescript", "python", "shell", "sql", "diff", "post", "space", "quip", "canvas", "email"}

USAGE = """usage: slack channels
       slack dms
       slack users
       slack history <channel> [count]
       slack thread <channel> <ts> [after-ts]
       slack message <channel> <ts>
       slack search <query>...
       slack scopes
a channel is its id, such as C0123ABCD or a DM's D0123ABCD, or a channel's name, such as general"""


class Failure(Exception):
    pass


def usage():
    print(USAGE, file=sys.stderr)
    sys.exit(2)


class Slack:
    """The Web API, read-only. Tests replace `fetch`."""

    def __init__(self, token):
        self.token = token
        self.scopes = None
        self.users = None

    def fetch(self, url):
        """GETs `url` with the token, returning (body bytes, headers dict)."""
        request = urllib.request.Request(url, headers={"Authorization": f"Bearer {self.token}"})
        for attempt in range(4):
            try:
                with urllib.request.urlopen(request, timeout=30) as response:
                    return response.read(FILE_BYTES + 1), {key.lower(): value for key, value in response.headers.items()}
            except urllib.error.HTTPError as error:
                if error.code == 429 and attempt < 3:
                    time.sleep(min(int(error.headers.get("Retry-After") or 5), 20))
                    continue
                raise Failure(f"HTTP {error.code} from {urllib.parse.urlsplit(url).netloc}")
            except urllib.error.URLError as error:
                raise Failure(f"could not reach Slack: {error.reason}")
        raise Failure("Slack kept rate limiting")

    def call(self, method, **params):
        body, headers = self.fetch(API + method + "?" + urllib.parse.urlencode({k: v for k, v in params.items() if v not in (None, "")}))
        data = json.loads(body)
        if not data.get("ok"):
            raise Failure(f"{method} failed: {data.get('error') or 'unknown error'}")
        if "x-oauth-scopes" in headers and self.scopes is None:
            self.scopes = {scope.strip() for scope in headers["x-oauth-scopes"].split(",") if scope.strip()}
        return data

    def pages(self, method, key, **params):
        cursor = ""
        for _ in range(MAX_PAGES):
            data = self.call(method, limit=200, cursor=cursor, **params)
            yield from data.get(key) or []
            cursor = (data.get("response_metadata") or {}).get("next_cursor") or ""
            if not cursor:
                return

    def granted(self):
        if self.scopes is None:
            self.call("auth.test")
        return self.scopes or set()

    def names(self):
        if self.users is None:
            self.users = {}
            for user in self.pages("users.list", "members"):
                profile = user.get("profile") or {}
                self.users[user["id"]] = profile.get("display_name") or user.get("real_name") or profile.get("real_name") or user.get("name") or user["id"]
        return self.users

    def name(self, uid):
        return self.names().get(uid, uid) if uid else ""


# Rendering


def readable(slack, text):
    """Slack's mrkdwn markup made plain: mentions named, links shown, entities decoded."""
    text = re.sub(r"<@([A-Z0-9]+)(\|[^>]*)?>", lambda m: "@" + slack.name(m.group(1)), text or "")
    text = re.sub(r"<#[A-Z0-9]+\|([^>]*)>", r"#\1", text)
    text = re.sub(r"<!subteam\^[A-Z0-9]+\|?([^>]*)>", lambda m: m.group(1) or "@group", text)
    text = re.sub(r"<!([a-z]+)(\|[^>]*)?>", r"@\1", text)
    text = re.sub(r"<([^|>]+)\|([^>]*)>", r"\2 (\1)", text)
    text = re.sub(r"<([^>]+)>", r"\1", text)
    return text.replace("&lt;", "<").replace("&gt;", ">").replace("&amp;", "&")


def inline(slack, element):
    kind = element.get("type")
    if kind == "text":
        return element.get("text") or ""
    if kind == "link":
        url, label = element.get("url") or "", element.get("text") or ""
        return f"{label} ({url})" if label and label != url else url
    if kind == "user":
        return "@" + slack.name(element.get("user_id"))
    if kind == "channel":
        return "#" + (element.get("channel_id") or "")
    if kind == "usergroup":
        return "@group"
    if kind == "broadcast":
        return "@" + (element.get("range") or "here")
    if kind == "emoji":
        return element.get("unicode") and chr_emoji(element["unicode"]) or f":{element.get('name')}:"
    if kind == "date":
        return element.get("fallback") or str(element.get("timestamp") or "")
    if kind == "color":
        return element.get("value") or ""
    return element.get("text") or ""


def chr_emoji(code):
    try:
        return "".join(chr(int(part, 16)) for part in code.split("-"))
    except ValueError:
        return ""


def rich(slack, element, depth=0):
    """One rich_text element: a section, list, quote or code block, as plain lines."""
    kind = element.get("type")
    parts = element.get("elements") or []
    if kind == "rich_text_section":
        return "".join(inline(slack, part) for part in parts)
    if kind == "rich_text_preformatted":
        return "```\n" + "".join(inline(slack, part) for part in parts) + "\n```"
    if kind == "rich_text_quote":
        return "\n".join("> " + line for line in "".join(inline(slack, part) for part in parts).split("\n"))
    if kind == "rich_text_list":
        indent = "  " * (element.get("indent") or 0)
        lines = []
        for number, item in enumerate(parts, start=(element.get("offset") or 0) + 1):
            mark = f"{number}." if element.get("style") == "ordered" else "-"
            lines.append(f"{indent}{mark} {rich(slack, item, depth + 1)}")
        return "\n".join(lines)
    return "".join(inline(slack, part) for part in parts)


def blocks_text(slack, blocks):
    out = []
    for block in blocks or []:
        kind = block.get("type")
        if kind == "rich_text":
            text = ""
            for element in block.get("elements") or []:
                piece = rich(slack, element)
                # A section's own trailing newline already ends its line before a list, quote or code block.
                text += piece if not text or text.endswith("\n") else "\n" + piece
            out.append(text)
        elif kind in ("section", "header", "context"):
            texts = [block.get("text") or {}] + list(block.get("fields") or []) + list(block.get("elements") or [])
            out.append("\n".join(readable(slack, item.get("text") or "") for item in texts if isinstance(item, dict) and item.get("text")))
        elif kind == "markdown":
            out.append(block.get("text") or "")
    return "\n".join(piece for piece in out if piece).strip()


def body(slack, message):
    """The fullest of a message's rich text blocks and its text field."""
    from_blocks = blocks_text(slack, message.get("blocks"))
    from_text = readable(slack, message.get("text") or "").strip()
    return from_blocks if len(from_blocks) >= len(from_text) else from_text


def attachment_text(slack, attachment):
    """A shared message or a link unfurl, whole."""
    lines = []
    if attachment.get("is_msg_unfurl") or attachment.get("is_share") or attachment.get("message_blocks"):
        who = attachment.get("author_name") or attachment.get("author_subname") or slack.name(attachment.get("author_id")) or "someone"
        where = attachment.get("channel_name") or attachment.get("channel_id") or ""
        lines.append(f"[shared message from {who}{' in #' + where if where else ''}{', ts=' + attachment['ts'] if attachment.get('ts') else ''}]")
        inner = ""
        for item in attachment.get("message_blocks") or []:
            inner = blocks_text(slack, (item.get("message") or {}).get("blocks")) or inner
        text = readable(slack, attachment.get("text") or "")
        inner = inner if len(inner) >= len(text) else text
        lines += ["> " + line for line in inner.split("\n")]
        for item in attachment.get("files") or []:
            lines.append(f"> [file: {item.get('name') or item.get('title') or 'file'}]")
        return "\n".join(lines)
    title = attachment.get("title") or attachment.get("pretext") or ""
    link = attachment.get("title_link") or attachment.get("from_url") or attachment.get("original_url") or ""
    head = " ".join(filter(None, [attachment.get("service_name") and f"{attachment['service_name']}:", title, link and f"({link})"]))
    lines.append(f"[link preview] {head}".rstrip() if head else "[attachment]")
    text = readable(slack, attachment.get("text") or "") or blocks_text(slack, attachment.get("blocks")) or readable(slack, attachment.get("fallback") or "")
    if text:
        lines += ["  " + line for line in text.split("\n")]
    for field in attachment.get("fields") or []:
        lines.append(f"  {field.get('title') or ''}: {readable(slack, field.get('value') or '')}")
    return "\n".join(lines)


def strip_html(text):
    text = re.sub(r"(?is)<(script|style)[^>]*>.*?</\1>", "", text)
    text = re.sub(r"(?i)<br\s*/?>|</(p|div|h[1-6]|li|tr|pre|blockquote)>", "\n", text)
    text = re.sub(r"(?i)<li[^>]*>", "- ", text)
    text = re.sub(r"<[^>]+>", "", text)
    text = html.unescape(text)
    return re.sub(r"\n{3,}", "\n\n", text).strip()


def readable_file(item):
    filetype = (item.get("filetype") or "").lower()
    mimetype = (item.get("mimetype") or "").lower()
    return item.get("mode") in ("snippet", "post", "space", "canvas", "quip") or filetype in TEXT_TYPES or mimetype.startswith("text/")


def file_text(slack, item):
    """A file's own text where Slack serves it: snippets, text files and canvases, with files:read."""
    if item.get("file_access") == "check_file_info" or (item.get("id") and not item.get("name") and not item.get("url_private")):
        if "files:read" not in slack.granted():
            return "", "files:read would show it"
        try:
            item = slack.call("files.info", file=item["id"]).get("file") or item
        except Failure as error:
            return "", str(error)
    if not readable_file(item):
        return "", ""
    preview = item.get("preview") or item.get("plain_text") or ""
    url = item.get("url_private_download") or item.get("url_private") or ""
    host = urllib.parse.urlsplit(url).hostname or ""
    if url and host in FILE_HOSTS and "files:read" in slack.granted() and (item.get("size") or 0) <= FILE_BYTES:
        try:
            data, headers = slack.fetch(url)
        except Failure as error:
            return preview, f"could not fetch it ({error}), showing Slack's preview"
        text = data[:FILE_BYTES].decode("utf-8", "replace")
        is_html = "html" in (headers.get("content-type") or "") or text.lstrip()[:15].lower().startswith(("<!doctype", "<html"))
        if is_html and (item.get("filetype") or "") not in ("html", "quip", "canvas") and item.get("mode") not in ("canvas", "quip", "space"):
            return preview, "Slack answered with a sign-in page, showing its preview"
        return (strip_html(text) if is_html else text), ""
    if preview:
        more = " (Slack's preview only; files:read would show it whole)" if "files:read" not in slack.granted() or item.get("lines_more") else ""
        return preview, more.strip(" ()")
    return "", "files:read would show its text" if "files:read" not in slack.granted() else ""


def files_text(slack, message):
    lines = []
    for item in message.get("files") or []:
        name = item.get("title") or item.get("name") or "file"
        kind = item.get("pretty_type") or item.get("filetype") or item.get("mimetype") or ""
        lines.append(f"[file: {name}{' (' + kind + ')' if kind else ''}{', ' + item['permalink'] if item.get('permalink') else ''}]")
        text, note = file_text(slack, item)
        if text:
            if len(text) > FILE_TEXT:
                text, note = text[:FILE_TEXT], f"cut at {FILE_TEXT} characters of {len(text)}"
            lines += ["  | " + line for line in text.rstrip("\n").split("\n")]
        if note:
            lines.append(f"  ({note})")
    return "\n".join(lines)


def stamp(ts):
    return datetime.fromtimestamp(float(ts)).strftime("%Y-%m-%d %H:%M")


def author(slack, message):
    if message.get("user"):
        return slack.name(message["user"])
    return message.get("username") or (message.get("bot_profile") or {}).get("name") or "unknown"


def render(slack, message, where="", in_thread=False):
    head = f"[{stamp(message['ts'])}] {where}ts={message['ts']} {author(slack, message)}"
    if (message.get("reply_count") or 0) > 0 and message.get("thread_ts") == message["ts"]:
        head += f" (thread, {message['reply_count']} replies)"
    elif message.get("thread_ts") and message.get("thread_ts") != message["ts"] and not in_thread:
        head += f" (reply in thread {message['thread_ts']})"
    if message.get("edited"):
        head += " (edited)"
    parts = [head + ":", body(slack, message)]
    parts += [attachment_text(slack, item) for item in message.get("attachments") or []]
    parts.append(files_text(slack, message))
    return "\n".join(part for part in parts if part) + "\n"


class Out:
    """Prints messages until the daemon's limit nears, then says what it left out and how to read it."""

    def __init__(self, channel="", more=""):
        self.used = 0
        self.left = []
        self.channel = channel
        self.last = ""
        # How to read on from the last message shown, where the verb can.
        self.more = more

    def add(self, text, ts, channel=""):
        if self.left or self.used + len(text) > BUDGET:
            self.left.append((channel or self.channel, ts))
            return
        print(text)
        self.used += len(text) + 1
        self.last = ts

    def close(self):
        if self.left and self.more:
            print(f"[{len(self.left)} more messages not shown, to stay under the output limit; read on with `{self.more} {self.last}`]")
        elif self.left:
            shown = ", ".join(ts for _, ts in self.left[:20])
            print(f"[{len(self.left)} more messages not shown, to stay under the output limit; read each with `slack message <channel> <ts>`: {shown}{' …' if len(self.left) > 20 else ''}]")


# Verbs


def conversations(slack, types):
    return slack.pages("conversations.list", "channels", types=types, exclude_archived="true")


def channel(slack, given):
    if re.fullmatch(r"[CGD][A-Z0-9]{6,}", given):
        return given
    name = given.lstrip("#")
    if not re.fullmatch(r"[a-z0-9._-]+", name):
        usage()
    for item in conversations(slack, "public_channel,private_channel"):
        if item.get("name") == name:
            return item["id"]
    raise Failure(f"no channel named {name} that Aaron is in or can see")


def timestamp(given):
    if not re.fullmatch(r"[0-9]+\.[0-9]+", given):
        usage()
    return given


def thread(slack, cid, ts):
    return list(slack.pages("conversations.replies", "messages", channel=cid, ts=ts))


def find(slack, cid, ts):
    """One message by its ts, whether it starts a thread, stands alone or is a reply."""
    found = slack.call("conversations.history", channel=cid, latest=ts, oldest=ts, inclusive="true", limit=1).get("messages") or []
    for message in found:
        if message.get("ts") == ts:
            return message
    for message in thread(slack, cid, ts):
        if message.get("ts") == ts:
            return message
    raise Failure(f"no message ts={ts} in {cid} that Aaron can see")


def run(slack, args):
    if not args:
        usage()
    verb, rest = args[0], args[1:]
    if verb == "channels" and not rest:
        for item in conversations(slack, "public_channel,private_channel"):
            if item.get("is_member"):
                print("\t".join([item["id"], "#" + item.get("name", ""), "private" if item.get("is_private") else "public", f"{item.get('num_members') or 0} members", (item.get("topic") or {}).get("value") or ""]))
    elif verb == "dms" and not rest:
        for item in conversations(slack, "im,mpim"):
            if item.get("is_user_deleted"):
                continue
            label = "dm with " + slack.name(item.get("user")) if item.get("is_im") else "group dm " + ((item.get("purpose") or {}).get("value") or item.get("name") or "")
            print(f"{item['id']}\t{label}")
    elif verb == "users" and not rest:
        for user in slack.pages("users.list", "members"):
            if user.get("deleted") or user.get("is_bot") or user.get("id") == "USLACKBOT":
                continue
            print("\t".join([user["id"], user.get("name") or "", user.get("real_name") or "", (user.get("profile") or {}).get("title") or ""]))
    elif verb == "history" and 1 <= len(rest) <= 2:
        count = rest[1] if len(rest) == 2 else "20"
        if not re.fullmatch(r"[0-9]{1,3}", count) or not 1 <= int(count) <= 200:
            usage()
        cid = channel(slack, rest[0])
        messages = slack.call("conversations.history", channel=cid, limit=int(count)).get("messages") or []
        out = Out(cid)
        for message in sorted(messages, key=lambda item: float(item["ts"])):
            out.add(render(slack, message), message["ts"])
        out.close()
    elif verb == "thread" and len(rest) in (2, 3):
        cid, ts = channel(slack, rest[0]), timestamp(rest[1])
        after = float(timestamp(rest[2])) if len(rest) == 3 else None
        out = Out(cid, f"slack thread {cid} {ts}")
        for message in thread(slack, cid, ts):
            if after is None or float(message["ts"]) > after:
                out.add(render(slack, message, in_thread=message["ts"] != ts), message["ts"])
        out.close()
    elif verb == "message" and len(rest) == 2:
        cid, ts = channel(slack, rest[0]), timestamp(rest[1])
        text = render(slack, find(slack, cid, ts))
        if len(text) > BUDGET:
            text = text[:BUDGET] + f"\n[cut at {BUDGET} of {len(text)} characters, the daemon's output limit]"
        print(text)
    elif verb == "search" and rest:
        matches = (slack.call("search.messages", query=" ".join(rest), count=20, sort="timestamp", sort_dir="desc").get("messages") or {}).get("matches") or []
        out = Out()
        for match in matches:
            where = match.get("channel") or {}
            label = "dm " if where.get("is_im") else ("group dm " if where.get("is_mpim") else f"#{where.get('name') or '?'} ")
            # A search match carries the message's text, and blocks and files where Slack includes them; its own copy is read for the rest.
            message = match
            if where.get("id") and not match.get("blocks"):
                try:
                    message = {**find(slack, where["id"], match["ts"]), **{"ts": match["ts"]}}
                except Failure:
                    message = match
            out.add(render(slack, message, f"{label}channel={where.get('id') or '?'} "), match["ts"], where.get("id") or "")
        out.close()
    elif verb == "scopes" and not rest:
        answer = slack.call("auth.test")
        granted = slack.granted()
        print(f"token for {slack.name(answer.get('user_id')) or answer.get('user')} in {answer.get('team')}, a user token" if slack.token.startswith("xoxp-") else f"token for {answer.get('user')} in {answer.get('team')}")
        print("granted: " + (", ".join(sorted(granted)) or "unknown, Slack sent no scope header"))
        missing = [scope for scope in NEEDED if scope not in granted]
        print("missing, needed by slack: " + (", ".join(missing) or "none"))
        for scope, why in HELPFUL.items():
            if scope not in granted:
                print(f"would help, read-only: {scope}, for {why}")
    else:
        usage()


def main(argv):
    try:
        with open(CREDENTIAL) as handle:
            token = handle.read().strip()
    except OSError:
        token = ""
    if not token:
        print("slack: no Slack token yet; Aaron has to run sudo butler-slack-login on spike, pasting his xoxp- user token, or sudo butler-slack-login --from-index to reuse the index's", file=sys.stderr)
        return 78
    try:
        run(Slack(token), argv)
    except Failure as error:
        print(f"slack: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
