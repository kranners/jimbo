# Lists, creates, updates and deletes Home Assistant zones through its
# websocket API, the only API that edits them. The token is read from the
# credential file named by HOME_ASSISTANT_TOKEN_FILE and never printed.
import json
import math
import os
import re
import sys

from websockets.sync.client import connect

URL = "ws://127.0.0.1:8123/api/websocket"

USAGE = """usage: home zone list
       home zone create <name> <lat> <lng> <radius_m> [icon]
       home zone update <name> <lat> <lng> <radius_m> [icon]
       home zone rename <name> <new name>
       home zone delete <name>
icon is an mdi icon such as mdi:briefcase; radius is 10 to 5000 metres"""


def usage():
    print(USAGE, file=sys.stderr)
    sys.exit(2)


def refuse(message):
    print(f"home: {message}", file=sys.stderr)
    sys.exit(77)


def is_home(name):
    return name.strip().casefold() == "home"


def check_name(name):
    if not 1 <= len(name) <= 50 or re.search(r"[\x00-\x1f\x7f]", name):
        refuse("a zone name is 1 to 50 characters with no control characters")
    if is_home(name):
        refuse(
            "the Home zone is Home Assistant's own location, set by Aaron in "
            "/var/lib/hass/secrets.yaml, so it cannot be changed from here"
        )
    return name


def number(text, low, high, what):
    try:
        value = float(text)
    except ValueError:
        usage()
    if not math.isfinite(value) or not low <= value <= high:
        refuse(f"{what} must be between {low} and {high}")
    return value


def place(args):
    if len(args) not in (3, 4):
        usage()
    fields = {
        "latitude": number(args[0], -90, 90, "latitude"),
        "longitude": number(args[1], -180, 180, "longitude"),
        "radius": number(args[2], 10, 5000, "radius"),
    }
    if len(args) == 4:
        if not re.fullmatch(r"mdi:[a-z0-9-]{1,60}", args[3]):
            refuse("icon must look like mdi:map-marker")
        fields["icon"] = args[3]
    return fields


class HomeAssistant:
    def __init__(self):
        path = os.environ["HOME_ASSISTANT_TOKEN_FILE"]
        with open(path) as file:
            token = file.read().strip()
        self.socket = connect(URL, max_size=2**24)
        self.socket.recv()
        self.socket.send(json.dumps({"type": "auth", "access_token": token}))
        reply = json.loads(self.socket.recv())
        if reply.get("type") != "auth_ok":
            refuse("Home Assistant refused the token")
        self.next_id = 1

    def call(self, kind, **fields):
        self.next_id += 1
        self.socket.send(json.dumps({"id": self.next_id, "type": kind, **fields}))
        while True:
            reply = json.loads(self.socket.recv())
            if reply.get("id") == self.next_id and reply.get("type") == "result":
                break
        if not reply.get("success"):
            error = reply.get("error", {})
            if error.get("code") == "unauthorized":
                refuse(
                    "editing zones needs the token's user to be an "
                    "administrator in Home Assistant"
                )
            refuse(f"Home Assistant refused {kind}: {error.get('message')}")
        return reply.get("result")

    def find(self, name):
        if is_home(name):
            check_name(name)
        matches = [
            zone for zone in self.call("zone/list")
            if zone["name"].casefold() == name.strip().casefold()
        ]
        if not matches:
            refuse(f"no zone is named {name!r}; see home zone list")
        return matches[0]


def show(zone):
    return "\t".join([
        zone.get("name", ""),
        f"{zone['latitude']:.6f}",
        f"{zone['longitude']:.6f}",
        f"{zone['radius']:g} m",
        zone.get("icon") or "",
    ])


def main(args):
    if not args:
        usage()
    verb, args = args[0], args[1:]
    if verb == "list" and not args:
        ha = HomeAssistant()
        for state in ha.call("get_states"):
            if state["entity_id"] == "zone.home":
                attributes = state["attributes"]
                print(show({
                    "name": attributes.get("friendly_name", "Home"),
                    **attributes,
                }) + "\t(Home Assistant's own location, read-only)")
        for zone in ha.call("zone/list"):
            print(show(zone))
    elif verb == "create" and len(args) >= 1:
        name = check_name(args[0])
        fields = place(args[1:])
        ha = HomeAssistant()
        if any(z["name"].casefold() == name.casefold()
               for z in ha.call("zone/list")):
            refuse(f"a zone named {name!r} exists; use home zone update")
        fields.setdefault("icon", "mdi:map-marker")
        print("Created", show(ha.call("zone/create", name=name, **fields)))
    elif verb == "update" and len(args) >= 1:
        fields = place(args[1:])
        ha = HomeAssistant()
        zone = ha.find(args[0])
        print("Updated", show(ha.call(
            "zone/update", zone_id=zone["id"], **fields)))
    elif verb == "rename" and len(args) == 2:
        new = check_name(args[1])
        ha = HomeAssistant()
        zone = ha.find(args[0])
        print("Renamed", show(ha.call(
            "zone/update", zone_id=zone["id"], name=new)))
    elif verb == "delete" and len(args) == 1:
        ha = HomeAssistant()
        zone = ha.find(args[0])
        ha.call("zone/delete", zone_id=zone["id"])
        print("Deleted", show(zone))
    else:
        usage()


main(sys.argv[1:])
