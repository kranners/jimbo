#!/usr/bin/env python3
import sys
import subprocess
import json


def run_pw_dump():
    result = subprocess.run(["pw-dump"], capture_output=True, text=True, check=True)
    return json.loads(result.stdout)


def output_devices(pipewire_nodes):
    for node in pipewire_nodes:
        if not node.get("type") == "PipeWire:Interface:Node":
            continue

        props = node.get("info", {}).get("props", {})

        if not props.get("media.class") == "Audio/Sink":
            continue

        yield node["id"], props.get("node.description", props.get("node.name", ""))


def default_output_device_id():
    result = subprocess.run(
        ["wpctl", "inspect", "@DEFAULT_AUDIO_SINK@"], capture_output=True, text=True
    )

    if result.returncode != 0:
        return None

    return int(result.stdout.split(",", 1)[0].removeprefix("id "))


def set_default(id):
    subprocess.run(["wpctl", "set-default", str(id)], check=True)


def status(devices):
    default_id = default_output_device_id()
    descriptions = dict(devices)

    json.dump(
        {
            "description": descriptions.get(default_id, "No output device"),
            "count": len(descriptions),
        },
        sys.stdout,
        separators=(",", ":"),
    )


def cycle(devices):
    if not devices:
        return

    ids = [id for id, _ in devices]
    default_id = default_output_device_id()
    next_index = (ids.index(default_id) + 1) % len(ids) if default_id in ids else 0

    set_default(ids[next_index])


def set_by_description(devices, device_description):
    for id, description in devices:
        if description == device_description:
            set_default(id)
            return

    subprocess.run(["notify-send", f"Output device {device_description} not found"])


devices = sorted(output_devices(run_pw_dump()))
argument = sys.argv[1]

if argument == "--status":
    status(devices)
elif argument == "--cycle":
    cycle(devices)
else:
    set_by_description(devices, argument)
