"""Let Home Assistant on spike read the panel's brightness and run `panel` over HTTP."""

import subprocess
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

SPIKE_ADDRESS = "10.100.0.1"
PANEL_ARGUMENTS = {("on",), ("off",), ("schedule",)}

panel_command, port = sys.argv[1], int(sys.argv[2])


def run(*command):
    return subprocess.run(command, capture_output=True, text=True)


class PanelHandler(BaseHTTPRequestHandler):
    def respond(self, status, body=""):
        encoded = body.encode()
        self.send_response(status)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def respond_with_brightness(self):
        result = run(panel_command, "status")
        if result.returncode == 0:
            first_line = result.stdout.splitlines()[0]
            self.respond(200, first_line.removeprefix("brightness ").removesuffix("%"))
        else:
            self.respond(500, result.stderr)

    def is_from_spike(self):
        if self.client_address[0] == SPIKE_ADDRESS:
            return True
        self.respond(403)
        return False

    def do_GET(self):
        if not self.is_from_spike():
            return
        if self.path == "/brightness":
            self.respond_with_brightness()
        else:
            self.respond(404)

    def do_POST(self):
        if not self.is_from_spike():
            return
        arguments = tuple(self.path.strip("/").split("/"))
        is_brightness = len(arguments) == 2 and arguments[0] == "brightness"
        if arguments not in PANEL_ARGUMENTS and not is_brightness:
            self.respond(404)
            return
        result = run(panel_command, *arguments)
        if result.returncode == 0:
            self.respond_with_brightness()
        else:
            self.respond(400, result.stderr)


HTTPServer(("0.0.0.0", port), PanelHandler).serve_forever()
