"""A login in front of the sites spike serves to a device that should not get in on its address alone.

Caddy asks it about every request with forward_auth at /.gate/verify and proxies /.gate/* to it.
A device logs in once with Aaron's password and keeps a signed cookie for 30 days, bound to the site's host and to
the WireGuard peer it signed in from, named by the address Caddy forwards and the peers in DEVICE_GATE_PEERS.
The password is a scrypt hash in the credential `password`, and the signing key lives in the state directory,
so deleting the key logs every device out, while `revoke <peer>` signs one device out, recording the time in
`revoked.json` beside the key, so every cookie that peer was given before then stops working.
A site may sign devices in for less than 30 days, by its host in DEVICE_GATE_LIFETIMES, and a verified request
answers with X-Device-Gate-Device naming the peer, which Caddy copies to the site so it knows which device it is.
"""

import base64
import hashlib
import hmac
import html
import json
import os
import secrets
import socket
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, quote, urlparse

COOKIE = "__Host-device-gate"
LIFETIME = 30 * 24 * 3600
FAILURE_WINDOW = 15 * 60
MAX_FAILURES = 10
FAILURE_DELAY = 1.0
SYSTEMD_FIRST_SOCKET = 3
POLICY = "default-src 'none'; style-src 'unsafe-inline'; img-src 'self'; form-action 'self'; frame-ancestors 'none'; base-uri 'none'"


def hash_password(password, salt=None, n=2**15, r=8, p=1):
    salt = salt or secrets.token_bytes(16)
    digest = hashlib.scrypt(password.encode(), salt=salt, n=n, r=r, p=p, maxmem=64 * 1024 * 1024, dklen=32)
    return f"scrypt${n}${r}${p}${base64.b64encode(salt).decode()}${base64.b64encode(digest).decode()}"


def check_password(password, stored):
    try:
        kind, n, r, p, salt, digest = stored.strip().split("$")
        if kind != "scrypt":
            return False
        expected = base64.b64decode(digest)
        actual = hashlib.scrypt(password.encode(), salt=base64.b64decode(salt), n=int(n), r=int(r), p=int(p), maxmem=64 * 1024 * 1024, dklen=len(expected))
    except (ValueError, TypeError):
        return False
    return hmac.compare_digest(actual, expected)


def sign(key, host, expires, issued, device):
    message = f"{host}|{expires}|{issued}|{device}".encode()
    return base64.urlsafe_b64encode(hmac.new(key, message, hashlib.sha256).digest()).decode().rstrip("=")


def make_cookie(key, host, now, device, lifetime=LIFETIME):
    issued = int(now)
    expires = issued + lifetime
    return f"{expires}.{issued}.{sign(key, host, expires, issued, device)}"


def cookie_valid(key, host, value, now, device, revoked_at=0):
    try:
        expires, issued, signature = value.split(".", 2)
        expires, issued = int(expires), int(issued)
    except (AttributeError, ValueError):
        return False
    return expires > now and issued > revoked_at and hmac.compare_digest(signature, sign(key, host, expires, issued, device))


def read_cookie(header, name=COOKIE):
    for part in (header or "").split(";"):
        key, _, value = part.strip().partition("=")
        if key == name:
            return value
    return None


def safe_next(target):
    # Only a path on the same site, never another origin or a scheme-relative URL.
    if not target or not target.startswith("/") or target.startswith("//") or "\\" in target:
        return "/"
    return target


class Failures:
    def __init__(self):
        self.lock = threading.Lock()
        self.times = []

    def locked(self, now):
        with self.lock:
            self.times = [moment for moment in self.times if now - moment < FAILURE_WINDOW]
            return len(self.times) >= MAX_FAILURES

    def add(self, now):
        with self.lock:
            self.times.append(now)


class Gate:
    def __init__(self, password_file, key_file, peers=None, lifetimes=None):
        self.password_file = password_file
        self.lifetimes = lifetimes or {}
        self.key_file = key_file
        self.revoked_file = os.path.join(os.path.dirname(key_file), "revoked.json")
        self.peers = peers or {}
        self.failures = Failures()

    def device(self, forwarded_for):
        # Caddy sets X-Forwarded-For to the WireGuard address the request came from; the last entry is its own.
        address = (forwarded_for or "").split(",")[-1].strip()
        return self.peers.get(address, f"unknown {address}" if address else "unknown")

    def lifetime(self, host):
        return min(int(self.lifetimes.get(host, LIFETIME)), LIFETIME)

    def revoked_at(self, device):
        try:
            with open(self.revoked_file) as handle:
                return int(json.load(handle).get(device, 0))
        except (FileNotFoundError, ValueError, TypeError, AttributeError):
            return 0

    def key(self):
        try:
            with open(self.key_file, "rb") as handle:
                key = handle.read()
            if len(key) >= 32:
                return key
        except FileNotFoundError:
            pass
        key = secrets.token_bytes(32)
        descriptor = os.open(self.key_file, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(descriptor, "wb") as handle:
            handle.write(key)
        return key

    def stored_password(self):
        with open(self.password_file) as handle:
            return handle.read().strip()


def lasts(seconds):
    if seconds % 86400 == 0:
        days = seconds // 86400
        return f"{days} day" + ("" if days == 1 else "s")
    hours = max(1, seconds // 3600)
    return f"{hours} hour" + ("" if hours == 1 else "s")


def login_page(host, target, message="", lifetime=LIFETIME):
    note = f'<p class="note">{html.escape(message)}</p>' if message else ""
    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="robots" content="noindex">
<meta name="referrer" content="no-referrer">
<meta name="apple-mobile-web-app-capable" content="yes">
<title>Sign in to {html.escape(host)}</title>
<style>
:root {{ color-scheme: light dark; --page: #f5f4f1; --card: #fff; --text: #1b1b1a; --muted: #5f5e5a; --line: #d9d7d1; --accent: #1f6f73; }}
@media (prefers-color-scheme: dark) {{ :root {{ --page: #111110; --card: #1a1a19; --text: #ecebe8; --muted: #a3a29d; --line: #34332f; --accent: #3aa5ab; }} }}
body {{ margin: 0; min-height: 100vh; display: grid; place-items: center; padding: env(safe-area-inset-top) 20px env(safe-area-inset-bottom); background: var(--page); color: var(--text); font: 17px/1.45 system-ui, -apple-system, sans-serif; }}
form {{ width: min(360px, 100%); display: grid; gap: 14px; background: var(--card); border: 1px solid var(--line); border-radius: 16px; padding: 24px; }}
h1 {{ margin: 0; font-size: 20px; }}
p {{ margin: 0; color: var(--muted); font-size: 15px; }}
.note {{ color: #b3261e; }}
input, button {{ font: inherit; min-height: 48px; border-radius: 10px; }}
input {{ border: 1px solid var(--line); padding: 0 14px; background: var(--page); color: var(--text); }}
button {{ border: 0; background: var(--accent); color: #fff; font-weight: 600; }}
</style>
</head>
<body>
<form method="post" action="/.gate/login">
<h1>{html.escape(host)}</h1>
<p>Sign in once on this device; it stays signed in for {lasts(lifetime)}.</p>
{note}
<input type="hidden" name="next" value="{html.escape(target)}">
<input type="password" name="password" autocomplete="current-password" placeholder="Password" required autofocus>
<button type="submit">Sign in</button>
</form>
</body>
</html>
""".encode()


def handler_for(gate, clock=time.time, sleep=time.sleep):
    class Handler(BaseHTTPRequestHandler):
        server_version = "device-gate"

        def address_string(self):
            return "caddy"

        def log_message(self, format, *arguments):
            pass

        def host(self):
            return self.headers.get("Host", "").lower()

        def finish_with(self, status, body=b"", kind="text/plain; charset=utf-8", headers=()):
            self.send_response(status)
            self.send_header("Content-Type", kind)
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Security-Policy", POLICY)
            self.send_header("X-Content-Type-Options", "nosniff")
            self.send_header("Referrer-Policy", "no-referrer")
            for name, value in headers:
                self.send_header(name, value)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def device(self):
            return gate.device(self.headers.get("X-Forwarded-For"))

        def signed_in(self):
            device = self.device()
            return cookie_valid(gate.key(), self.host(), read_cookie(self.headers.get("Cookie")), clock(), device, gate.revoked_at(device))

        def do_GET(self):
            url = urlparse(self.path)
            if url.path == "/.gate/verify":
                if self.signed_in():
                    return self.finish_with(200, headers=[("X-Device-Gate-Device", self.device())])
                original = self.headers.get("X-Forwarded-Uri", "/")
                if self.headers.get("X-Forwarded-Method", "GET") == "GET" and self.headers.get("Sec-Fetch-Mode", "navigate") == "navigate":
                    return self.finish_with(302, headers=[("Location", f"/.gate/login?next={quote(safe_next(original), safe='')}")])
                return self.finish_with(401, b"sign in first")
            if url.path == "/.gate/login":
                target = safe_next(parse_qs(url.query).get("next", ["/"])[0])
                if self.signed_in():
                    return self.finish_with(303, headers=[("Location", target)])
                return self.finish_with(200, login_page(self.host(), target, lifetime=gate.lifetime(self.host())), "text/html; charset=utf-8")
            if url.path == "/.gate/logout":
                return self.finish_with(303, headers=[("Location", "/.gate/login"), ("Set-Cookie", f"{COOKIE}=; Max-Age=0; Path=/; Secure; HttpOnly; SameSite=Strict")])
            return self.finish_with(404, b"not found")

        def do_POST(self):
            if urlparse(self.path).path != "/.gate/login":
                return self.finish_with(404, b"not found")
            length = int(self.headers.get("Content-Length") or 0)
            if length > 4096:
                return self.finish_with(413, b"too long")
            form = parse_qs(self.rfile.read(length).decode("utf-8", "replace"))
            target = safe_next(form.get("next", ["/"])[0])
            now = clock()
            if gate.failures.locked(now):
                print(f"refused a login from {self.device()} to {self.host()}: too many failures", file=sys.stderr, flush=True)
                return self.finish_with(429, login_page(self.host(), target, "Too many wrong passwords. Try again in 15 minutes.", gate.lifetime(self.host())), "text/html; charset=utf-8")
            if not check_password(form.get("password", [""])[0], gate.stored_password()):
                gate.failures.add(now)
                print(f"a wrong password from {self.device()} for {self.host()}", file=sys.stderr, flush=True)
                sleep(FAILURE_DELAY)
                return self.finish_with(403, login_page(self.host(), target, "That password is wrong.", gate.lifetime(self.host())), "text/html; charset=utf-8")
            print(f"signed {self.device()} in to {self.host()}", file=sys.stderr, flush=True)
            lifetime = gate.lifetime(self.host())
            cookie = f"{COOKIE}={make_cookie(gate.key(), self.host(), now, self.device(), lifetime)}; Max-Age={lifetime}; Path=/; Secure; HttpOnly; SameSite=Strict"
            return self.finish_with(303, headers=[("Location", target), ("Set-Cookie", cookie)])

    return Handler


def revoke(state_directory, device, clock=time.time):
    # Every cookie the device was given until now stops working; it can sign in again with the password.
    path = os.path.join(state_directory, "revoked.json")
    try:
        with open(path) as handle:
            revoked = json.load(handle)
    except (FileNotFoundError, ValueError):
        revoked = {}
    revoked[device] = int(clock())
    descriptor = os.open(f"{path}.new", os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(descriptor, "w") as handle:
        json.dump(revoked, handle)
    os.replace(f"{path}.new", path)
    print(f"signed {device} out", file=sys.stderr, flush=True)


class SocketServer(ThreadingHTTPServer):
    address_family = socket.AF_UNIX


def main():
    if len(sys.argv) == 2 and sys.argv[1] == "hash":
        print(hash_password(sys.stdin.readline().rstrip("\n")))
        return
    if len(sys.argv) == 4 and sys.argv[1] == "revoke":
        revoke(sys.argv[2], sys.argv[3])
        return
    peers = json.loads(os.environ.get("DEVICE_GATE_PEERS", "{}"))
    lifetimes = json.loads(os.environ.get("DEVICE_GATE_LIFETIMES", "{}"))
    gate = Gate(os.path.join(os.environ["CREDENTIALS_DIRECTORY"], "password"), os.path.join(os.environ["STATE_DIRECTORY"], "session-key"), peers, lifetimes)
    server = SocketServer(None, handler_for(gate), bind_and_activate=False)
    server.socket.close()
    server.socket = socket.socket(fileno=SYSTEMD_FIRST_SOCKET)
    server.serve_forever()


if __name__ == "__main__":
    main()
