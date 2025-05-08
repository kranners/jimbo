#!/usr/bin/env python3
import sys
import subprocess
import json


def run_pw_dump():
    result = subprocess.run(["pw-dump"], capture_output=True, text=True, check=True)
    return json.loads(result.stdout)


def set_output_device(pipewire_nodes, device_description):
    for node in pipewire_nodes:
        if not node.get("type") == "PipeWire:Interface:Node":
            continue

        props = node.get("info", {}).get("props", {})

        if not props.get("media.class") == "Audio/Sink":
            continue

        if props.get("node.description") == device_description:
            id = node["id"]
            subprocess.run(["wpctl", "set-default", str(id)], check=True)
            return

    subprocess.run(["notify-send", f"Output device {device_description} not found"])


pipewire_nodes = run_pw_dump()
device_description = sys.argv[1]
output_device_names = set_output_device(pipewire_nodes, device_description)
