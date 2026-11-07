import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from collections import defaultdict
from datetime import date, datetime, time, timedelta
from zoneinfo import ZoneInfo

# Read-only by construction: every request is a GET under this base, and a pagination link
# elsewhere is refused, so nothing here can move money.
UP_API = "https://api.up.com.au/api/v1"
SECRET = "/var/lib/secrets/butler-index-up-token"
CREDENTIAL = "up-token"
ZONE = ZoneInfo("Australia/Melbourne")
TIMEOUT_SECONDS = 30
MAX_PAGES = 50
EX_USAGE = 2
EX_TEMPFAIL = 75
EX_CONFIG = 78

USAGE = """usage: up accounts
       up transactions [from YYYY-MM-DD] [to YYYY-MM-DD] [account <name>] [match <text>] [category <id>] [limit N]
       up spending <from YYYY-MM-DD> <to YYYY-MM-DD> [account <name>]
       up categories
       up shared <group> [from YYYY-MM-DD] [to YYYY-MM-DD] [split N]"""


def die(message, code=1):
    print(f"up: {message}", file=sys.stderr)
    sys.exit(code)


def usage():
    print(USAGE, file=sys.stderr)
    sys.exit(EX_USAGE)


def token():
    try:
        with open(os.path.join(os.environ["CREDENTIALS_DIRECTORY"], CREDENTIAL)) as file:
            value = file.read().strip()
    except (KeyError, OSError):
        value = ""
    if not value:
        die(f"no Up token yet; Aaron has to write his Up personal access token to {SECRET} on spike and restart butler", EX_CONFIG)
    return value


def get(url, params=None):
    if not url.startswith(UP_API + "/"):
        die("refusing a link outside Up's API")
    if params:
        url += "?" + urllib.parse.urlencode(params)
    request = urllib.request.Request(url, method="GET", headers={"Authorization": f"Bearer {token()}", "Accept": "application/json"})
    try:
        with urllib.request.urlopen(request, timeout=TIMEOUT_SECONDS) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        if error.code == 401:
            die("Up refused the token (HTTP 401); it needs a new personal access token", EX_CONFIG)
        if error.code == 429 or error.code >= 500:
            die(f"Up is unavailable right now (HTTP {error.code}); try again shortly", EX_TEMPFAIL)
        die(f"Up answered HTTP {error.code}")
    except (urllib.error.URLError, TimeoutError) as error:
        die(f"could not reach Up: {getattr(error, 'reason', error)}", EX_TEMPFAIL)


def pages(path, params, limit=None):
    url, page_params, count = f"{UP_API}/{path}", params, 0
    for _ in range(MAX_PAGES):
        page = get(url, page_params)
        page_params = None
        for item in page.get("data", []):
            yield item
            count += 1
            if limit is not None and count >= limit:
                return
        url = (page.get("links") or {}).get("next")
        if not url:
            return


def money(value):
    sign = "-" if value < 0 else ""
    return f"{sign}${abs(value):,.2f}"


def day(text):
    if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", text):
        usage()
    try:
        return date.fromisoformat(text)
    except ValueError:
        usage()


def bound(d):
    return datetime.combine(d, time(), ZONE).isoformat()


def options(args, allowed):
    found = {}
    i = 0
    while i < len(args):
        key = args[i]
        if key not in allowed or i + 1 >= len(args) or key in found:
            usage()
        found[key] = args[i + 1]
        i += 2
    return found


def accounts():
    return list(pages("accounts", {"page[size]": "100"}))


def account_id(name):
    wanted = name.strip().lower()
    matches = [a for a in accounts() if wanted in a["attributes"]["displayName"].lower()]
    if not matches:
        die(f"no Up account named like {name!r}; run `up accounts`")
    exact = [a for a in matches if a["attributes"]["displayName"].lower() == wanted]
    if len(exact) == 1:
        return exact[0]["id"]
    if len(matches) > 1:
        die(f"{name!r} matches several accounts: " + ", ".join(a["attributes"]["displayName"] for a in matches))
    return matches[0]["id"]


def relation(transaction, name):
    return (((transaction.get("relationships") or {}).get(name) or {}).get("data") or {}).get("id")


def transactions(since, until, account=None, category=None, limit=None):
    params = {"page[size]": "100"}
    if since:
        params["filter[since]"] = bound(since)
    if until:
        params["filter[until]"] = bound(until + timedelta(days=1))
    if category:
        params["filter[category]"] = category
    path = f"accounts/{account}/transactions" if account else "transactions"
    return pages(path, params, limit)


def show_accounts():
    rows = accounts()
    order = {"TRANSACTIONAL": 0, "SAVER": 1}
    total = 0.0
    for a in sorted(rows, key=lambda a: (order.get(a["attributes"]["accountType"], 2), a["attributes"]["displayName"])):
        attributes = a["attributes"]
        value = float(attributes["balance"]["value"])
        total += value
        kind = {"TRANSACTIONAL": "spending", "SAVER": "saver"}.get(attributes["accountType"], attributes["accountType"].lower())
        owner = " (joint)" if attributes.get("ownershipType") == "JOINT" else ""
        print(f"{attributes['displayName']}\t{kind}{owner}\t{money(value)} {attributes['balance']['currencyCode']}")
    print(f"total\t\t{money(total)}")


def describe(transaction, names):
    attributes = transaction["attributes"]
    created = datetime.fromisoformat(attributes["createdAt"]).astimezone(ZONE)
    amount = float(attributes["amount"]["value"])
    category = relation(transaction, "category")
    transfer = relation(transaction, "transferAccount")
    parts = [
        created.strftime("%Y-%m-%d %H:%M"),
        money(amount),
        attributes.get("description") or "",
        names.get(relation(transaction, "account"), ""),
        f"transfer to/from {names.get(transfer, 'own account')}" if transfer else (category or "uncategorised"),
    ]
    if attributes.get("status") == "HELD":
        parts.append("pending")
    # The message on money coming in was written by whoever sent it, so it is shown as theirs.
    message = attributes.get("message")
    if message:
        parts.append(("note: " if amount < 0 else "sender's message: ") + message)
    return "\t".join(parts)


def show_transactions(args):
    found = options(args, {"from", "to", "account", "match", "category", "limit"})
    since = day(found["from"]) if "from" in found else None
    until = day(found["to"]) if "to" in found else None
    limit = found.get("limit", "25")
    if not re.fullmatch(r"\d{1,3}", limit) or not 1 <= int(limit) <= 500:
        usage()
    limit = int(limit)
    category = found.get("category")
    if category is not None and not re.fullmatch(r"[a-z0-9-]{1,60}", category):
        usage()
    account = account_id(found["account"]) if "account" in found else None
    names = {a["id"]: a["attributes"]["displayName"] for a in accounts()}
    text = found.get("match", "").lower()
    shown = 0
    # A text filter is applied here, so it reads further than the limit to find matches.
    for transaction in transactions(since, until, account, category, None if text else limit):
        attributes = transaction["attributes"]
        haystack = " ".join(filter(None, [attributes.get("description"), attributes.get("rawText"), attributes.get("message"), relation(transaction, "category")])).lower()
        if text and text not in haystack:
            continue
        print(describe(transaction, names))
        shown += 1
        if shown >= limit:
            break
    if not shown:
        print("no transactions match")


def show_spending(args):
    if len(args) < 2:
        usage()
    since, until = day(args[0]), day(args[1])
    if until < since:
        usage()
    found = options(args[2:], {"account"})
    account = account_id(found["account"]) if "account" in found else None
    spent = defaultdict(float)
    count = defaultdict(int)
    income = refunds = 0.0
    for transaction in transactions(since, until, account):
        # Moving money between Aaron's own accounts is neither spending nor income.
        if relation(transaction, "transferAccount"):
            continue
        amount = float(transaction["attributes"]["amount"]["value"])
        key = (relation(transaction, "parentCategory") or "uncategorised", relation(transaction, "category") or "uncategorised")
        if amount < 0:
            spent[key] += -amount
            count[key] += 1
        elif relation(transaction, "category"):
            refunds += amount
            spent[key] -= amount
        else:
            income += amount
    days = (until - since).days + 1
    total = sum(spent.values())
    print(f"{since} to {until} ({days} days)")
    print(f"spent\t{money(total)}\t{money(total / days)} a day")
    print(f"income\t{money(income)}")
    if refunds:
        print(f"refunds netted into categories\t{money(refunds)}")
    parents = defaultdict(float)
    for (parent, _), value in spent.items():
        parents[parent] += value
    for parent, value in sorted(parents.items(), key=lambda item: -item[1]):
        print(f"{parent}\t{money(value)}")
        for (p, child), v in sorted(spent.items(), key=lambda item: -item[1]):
            if p == parent and child != parent:
                print(f"  {child}\t{money(v)}\t{count[(p, child)]} transactions")


def show_categories():
    for category in pages("categories", None):
        parent = relation(category, "parent")
        print(f"{category['id']}\t{category['attributes']['name']}" + (f"\tin {parent}" if parent else ""))


def mentions(text, group):
    return bool(text) and group.lower() in text.lower()


def note_text(attributes):
    # Up's note is an object with its text on newer API versions; older answers have none.
    note = attributes.get("note")
    if isinstance(note, dict):
        return note.get("text") or ""
    return note if isinstance(note, str) else ""


def tags(transaction):
    data = ((transaction.get("relationships") or {}).get("tags") or {}).get("data") or []
    return [t.get("id", "") for t in data]


def shared_ledger(items, group, split):
    """Split a group's transactions into Aaron's shared purchases and the settlements others paid him.

    A purchase is shared when Aaron tagged it with the group's name in Up, or his note or message names it;
    money in counts as a settlement when its sender's message or its description names the group, as Rylee's
    'Sports team' payments do. Up's own slices are not in its public API, so this ledger only sees what tags
    and messages say."""
    purchases, settlements = [], []
    for transaction in items:
        attributes = transaction["attributes"]
        if relation(transaction, "transferAccount"):
            continue
        amount = float(attributes["amount"]["value"])
        texts = [attributes.get("message"), note_text(attributes)]
        tagged = any(t.lower() == group.lower() for t in tags(transaction))
        if amount < 0 and (tagged or any(mentions(t, group) for t in texts)):
            purchases.append(transaction)
        elif amount > 0 and (tagged or any(mentions(t, group) for t in texts + [attributes.get("description")])):
            settlements.append(transaction)
    total = sum(-float(t["attributes"]["amount"]["value"]) for t in purchases)
    owed = total * (split - 1) / split
    paid = defaultdict(float)
    for t in settlements:
        paid[t["attributes"].get("description") or "someone"] += float(t["attributes"]["amount"]["value"])
    return purchases, settlements, total, owed, dict(paid)


def show_shared(args):
    if not args:
        usage()
    group, found = args[0], options(args[1:], {"from", "to", "split"})
    if not re.fullmatch(r"[\w '&.-]{1,40}", group):
        usage()
    until = day(found["to"]) if "to" in found else datetime.now(ZONE).date()
    since = day(found["from"]) if "from" in found else until - timedelta(days=180)
    split = found.get("split", "2")
    if not re.fullmatch(r"\d{1,2}", split) or not 2 <= int(split) <= 20:
        usage()
    split = int(split)
    names = {a["id"]: a["attributes"]["displayName"] for a in accounts()}
    purchases, settlements, total, owed, paid = shared_ledger(transactions(since, until), group, split)
    print(f"{group}, {since} to {until}, split {split} ways (from Up tags and messages; Up's slices are not in its API)")
    print("shared purchases:")
    for t in purchases:
        print("  " + describe(t, names))
    if not purchases:
        print(f"  none tagged {group!r} or naming it in a note")
    print("settlements paid to Aaron:")
    for t in settlements:
        print("  " + describe(t, names))
    if not settlements:
        print("  none")
    received = sum(paid.values())
    print(f"shared total\t{money(total)}")
    print(f"others' share\t{money(owed)}")
    for person, value in sorted(paid.items()):
        print(f"paid by {person}\t{money(value)}")
    balance = owed - received
    if balance > 0.005:
        print(f"still owed to Aaron\t{money(balance)}")
    elif balance < -0.005:
        print(f"Aaron has been paid {money(-balance)} more than the tagged purchases' share; a purchase may be untagged")
    else:
        print("settled")


def main():
    args = sys.argv[1:]
    if not args:
        usage()
    verb, rest = args[0], args[1:]
    if verb == "accounts" and not rest:
        show_accounts()
    elif verb == "transactions":
        show_transactions(rest)
    elif verb == "spending":
        show_spending(rest)
    elif verb == "shared":
        show_shared(rest)
    elif verb == "categories" and not rest:
        show_categories()
    else:
        usage()


if __name__ == "__main__":
    main()
