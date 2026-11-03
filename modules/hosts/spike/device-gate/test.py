"""Checks the device gate end to end over HTTP, with a fake clock and no delay."""

import http.client
import os
import sys
import tempfile
import threading
from http.server import ThreadingHTTPServer

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gate  # noqa: E402

directory = tempfile.mkdtemp()
password_file = os.path.join(directory, "password")
with open(password_file, "w") as handle:
    handle.write(gate.hash_password("correct horse", n=2**10) + "\n")
now = [1_800_000_000.0]
state = gate.Gate(password_file, os.path.join(directory, "session-key"))
server = ThreadingHTTPServer(("127.0.0.1", 0), gate.handler_for(state, clock=lambda: now[0], sleep=lambda seconds: None))
threading.Thread(target=server.serve_forever, daemon=True).start()
port = server.server_address[1]


def request(method, path, headers=None, body=None, host="kanban.spike.cute.engineer"):
    connection = http.client.HTTPConnection("127.0.0.1", port)
    connection.request(method, path, body=body, headers={"Host": host, **(headers or {})})
    response = connection.getresponse()
    response.read()
    return response


def login(password, host="kanban.spike.cute.engineer"):
    body = f"password={password}&next=/board"
    return request("POST", "/.gate/login", {"Content-Type": "application/x-www-form-urlencoded", "Content-Length": str(len(body))}, body, host)


page = request("GET", "/.gate/verify", {"X-Forwarded-Method": "GET", "X-Forwarded-Uri": "/x?y=1", "Sec-Fetch-Mode": "navigate"})
assert page.status == 302 and page.getheader("Location") == "/.gate/login?next=%2Fx%3Fy%3D1", page.getheader("Location")
assert request("GET", "/.gate/verify", {"X-Forwarded-Method": "POST", "Sec-Fetch-Mode": "cors"}).status == 401
assert request("GET", "/.gate/verify", {"X-Forwarded-Method": "GET", "Sec-Fetch-Mode": "websocket"}).status == 401
assert request("GET", "/.gate/login?next=//evil.example").status == 200

wrong = login("nope")
assert wrong.status == 403 and wrong.getheader("Set-Cookie") is None
right = login("correct+horse")
assert right.status == 303 and right.getheader("Location") == "/board", right.status
cookie = right.getheader("Set-Cookie").split(";")[0]
assert "HttpOnly" in right.getheader("Set-Cookie") and "SameSite=Strict" in right.getheader("Set-Cookie")
assert request("GET", "/.gate/verify", {"Cookie": cookie}).status == 200
assert request("GET", "/.gate/verify", {"Cookie": cookie, "Sec-Fetch-Mode": "cors", "X-Forwarded-Method": "GET"}, host="life.spike.cute.engineer").status == 401
assert request("GET", "/.gate/verify", {"Cookie": cookie[:-2] + "xx", "Sec-Fetch-Mode": "cors"}).status == 401

now[0] += gate.LIFETIME + 1
assert request("GET", "/.gate/verify", {"Cookie": cookie, "Sec-Fetch-Mode": "cors"}).status == 401

os.remove(os.path.join(directory, "session-key"))
now[0] -= gate.LIFETIME
assert request("GET", "/.gate/verify", {"Cookie": cookie, "Sec-Fetch-Mode": "cors"}).status == 401

for _ in range(gate.MAX_FAILURES - 1):
    assert login("nope").status == 403
assert login("correct+horse").status == 429
now[0] += gate.FAILURE_WINDOW + 1
assert login("correct+horse").status == 303

assert gate.safe_next("/a") == "/a" and gate.safe_next("//b") == "/" and gate.safe_next("https://c") == "/" and gate.safe_next("/\\d") == "/"
print("device gate ok")
