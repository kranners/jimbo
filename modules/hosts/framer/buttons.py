import asyncio
import signal
import subprocess
import sys
import time

import evdev
from evdev import ecodes

DOUBLE_PRESS_SECONDS = 0.5
KEY_DOWN = 1

dismiss_command, toggle_command = sys.argv[1], sys.argv[2]


def button_devices():
    for path in evdev.list_devices():
        device = evdev.InputDevice(path)
        keys = device.capabilities().get(ecodes.EV_KEY, [])
        if ecodes.KEY_VOLUMEUP in keys or ecodes.KEY_POWER in keys:
            yield device


def run(command):
    subprocess.Popen([command])


async def watch(device, last_volume_up):
    async for event in device.async_read_loop():
        if event.type != ecodes.EV_KEY or event.value != KEY_DOWN:
            continue

        if event.code == ecodes.KEY_POWER:
            run(toggle_command)
        elif event.code == ecodes.KEY_VOLUMEUP:
            now = time.monotonic()
            if now - last_volume_up[0] < DOUBLE_PRESS_SECONDS:
                last_volume_up[0] = 0.0
                run(dismiss_command)
            else:
                last_volume_up[0] = now


async def main():
    devices = list(button_devices())
    if not devices:
        sys.exit("no volume or power button device found")

    last_volume_up = [0.0]
    await asyncio.gather(*(watch(device, last_volume_up) for device in devices))


signal.signal(signal.SIGCHLD, signal.SIG_IGN)
asyncio.run(main())
