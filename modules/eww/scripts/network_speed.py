#!/usr/bin/env python3
import sys
import time

direction = sys.argv[1]


def get_default_interface():
    with open("/proc/net/route") as f:
        for line in f.readlines():
            fields = line.strip().split()
            if fields[1] == "00000000" and int(fields[3], 16) & 2:
                return fields[0]
    return None


def get_rx_tx(device):
    with (
        open(f"/sys/class/net/{device}/statistics/rx_bytes") as rx,
        open(f"/sys/class/net/{device}/statistics/tx_bytes") as tx,
    ):
        return int(rx.read()), int(tx.read())


device = get_default_interface()
rx1, tx1 = get_rx_tx(device)
time.sleep(1)
rx2, tx2 = get_rx_tx(device)

if direction == "download":
    print(rx2 - rx1)
elif direction == "upload":
    print(tx2 - tx1)
