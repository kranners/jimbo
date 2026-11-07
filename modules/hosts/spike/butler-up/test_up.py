# Offline test of `up shared`: a group's tagged purchases and the settlements whose message names it make one
# ledger, transfers between Aaron's own accounts and unrelated money are left out, and nothing but GETs exist.
import contextlib
import importlib.util
import io
import re
import sys

spec = importlib.util.spec_from_file_location("up", sys.argv[1])
up = importlib.util.module_from_spec(spec)
spec.loader.exec_module(up)


def tx(id, amount, description, created, message=None, tags=(), transfer=None, note=None):
    attributes = {"amount": {"value": f"{amount:.2f}"}, "description": description, "createdAt": created, "message": message, "status": "SETTLED"}
    if note is not None:
        attributes["note"] = {"text": note}
    relationships = {"account": {"data": {"id": "spend"}}, "tags": {"data": [{"type": "tags", "id": t} for t in tags]}}
    if transfer:
        relationships["transferAccount"] = {"data": {"id": transfer}}
    return {"id": id, "attributes": attributes, "relationships": relationships}


fixture = [
    tx("1", -206.60, "Ticketek", "2026-10-28T10:00:00+11:00", tags=["Sports team"]),
    tx("2", -200.24, "Stadium bar", "2026-08-10T19:00:00+10:00", note="sports team drinks"),
    tx("3", -164.00, "Ticketek", "2026-10-10T09:00:00+11:00", tags=["Sports Team"]),
    tx("4", 103.30, "Rylee", "2026-07-08T12:00:00+10:00", message="Sports team"),
    tx("5", 100.12, "Rylee", "2026-08-18T12:00:00+10:00", message="Sports team"),
    tx("6", 82.00, "Rylee", "2026-10-16T12:00:00+11:00", message="Sports team"),
    tx("7", -50.00, "Groceries", "2026-10-11T12:00:00+11:00"),
    tx("8", -300.00, "Transfer to Holiday", "2026-10-12T12:00:00+11:00", tags=["Sports team"], transfer="saver"),
    tx("9", 20.00, "Sam", "2026-10-13T12:00:00+11:00", message="pizza"),
]

purchases, settlements, total, owed, paid = up.shared_ledger(fixture, "Sports team", 2)
assert [t["id"] for t in purchases] == ["1", "2", "3"], purchases
assert [t["id"] for t in settlements] == ["4", "5", "6"], settlements
assert abs(total - 570.84) < 0.001, total
assert abs(owed - 285.42) < 0.001, owed
assert paid == {"Rylee": 285.42}, paid

_, _, total3, owed3, _ = up.shared_ledger(fixture, "Sports team", 3)
assert abs(owed3 - 380.56) < 0.001, owed3

# The whole command against a fake Up, which also records that nothing but GETs under Up's API are made.
calls = []


def fake_get(url, params=None):
    calls.append(url)
    if url.endswith("/accounts"):
        return {"data": [{"id": "spend", "attributes": {"displayName": "Spending"}}]}
    if url.endswith("/transactions"):
        return {"data": fixture}
    raise AssertionError(url)


up.get = fake_get
out = io.StringIO()
with contextlib.redirect_stdout(out):
    up.show_shared(["Sports team", "from", "2026-07-01", "to", "2026-10-31"])
text = out.getvalue()
assert "shared total\t$570.84" in text, text
assert "paid by Rylee\t$285.42" in text, text
assert "settled" in text, text
assert "Groceries" not in text and "Holiday" not in text and "pizza" not in text, text

calls.clear()
fixture.pop(5)
out = io.StringIO()
with contextlib.redirect_stdout(out):
    up.show_shared(["Sports team", "split", "2"])
assert "still owed to Aaron\t$82.00" in out.getvalue(), out.getvalue()
assert all(c.startswith(up.UP_API + "/") for c in calls), calls

for bad in [[], ["Sports;team"], ["Sports team", "split", "1"], ["Sports team", "from", "yesterday"], ["Sports team", "limit", "3"]]:
    try:
        with contextlib.redirect_stderr(io.StringIO()):
            up.show_shared(bad)
    except SystemExit as exit:
        assert exit.code == up.EX_USAGE, (bad, exit.code)
    else:
        raise AssertionError(bad)

# Read-only by construction: the source never builds a request with any method but GET.
source = open(sys.argv[1]).read()
assert set(re.findall(r'method="([A-Z]+)"', source)) == {"GET"}, "up must only ever GET"
print("up shared: ok")
