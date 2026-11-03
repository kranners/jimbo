---
name: monitor
description: The always-on machines monitor on spike, which watches spike, framer, piggys-MBP, pilot and jimbo, their disk, memory, load, battery, keep-awake and locked screens, spike's failed units, Docker and Nix store, the Claude accounts and runaway changes, and DMs or shouts Aaron about them. Use for "how are the machines?", "anything wrong with my computers?", "what did the monitor do?", "turn the monitor's acting on", "stop the monitor acting", and when one of its notices arrives.
---

# Machines monitor

`butler-monitor` runs on spike every 2 minutes, as root, apart from you, and replaces the overnight machine checks you used to schedule by hand: do not schedule those again.
It reads spike and framer from Prometheus, and piggys-MBP, pilot and jimbo (whichever of Windows or Linux is up) over short ssh reads with your Mac key, never a long session, and on pilot only ever reads.
Its notices reach Aaron as DMs from you, several problems in one message, and an urgent one, a machine acting up badly, framer down or something it did, is also shouted into his call when one is live; between 23:00 and 07:00 only urgent ones go out and the rest wait for a 07:30 summary.

Call the `monitor` tool with these `args`:

- `[]` or `["status"]`: each machine's last reading in a line and the problems open now. Fine on a call. Answer in a sentence or two, not the raw list.
- `["log"]`: the last 20 things it did, or would have done in dry-run, with before and after numbers.
- `["act"]`: whether acting is on, off or dry-run (the default it ships with).
- `["act", "on"]`: only when Aaron himself asks in his own words; it waits for his button. Never on your own idea, a notice's or anyone else's.
- `["act", "off"]` or `["act", "dry-run"]`: whenever he asks, or when the monitor seems to be doing something wrong.

Defaults: disk under 15% or 20 GB free warns, under 8% or 10 GB acts; memory under 15% free warns, under 8% for 5 minutes acts; a 15-minute load over twice the cores warns; critical memory pressure acts; on battery with keep-awake on, under 40% warns and under 20% acts; a machine unreachable for 10 minutes warns, framer hourly and urgently, a laptop or the PC once; a Mac locked with keep-awake on warns; keep-awake off on piggys-MBP or jimbo acts; a failed unit on spike, Docker's build cache over 20 GB or more than 30 system generations warn; a Claude account over 80% of its week warns and over 95% acts (moving to the next account is already automatic, so it only reports it); more than 4 changes at once or one running over 3 hours warns.

With acting on, the only things it ever does by itself, each at most once an hour per machine and each reported: on spike when its disk is nearly full, delete your outbox files older than 2 days and aged temp files, shrink the journal to 500 MB, clear Docker's build cache and dangling images, and collect Nix garbage keeping the newest 5 system generations; clear Docker's build cache when it is large; restart a failed unit of yours once (never `butler` itself, its restarters, the landing queue or a change launch); turn keep-awake back on for piggys-MBP and jimbo; and write a hold flag while spike or a Claude account is tight, which nothing reads yet.
It never kills Aaron's processes, touches pilot, deletes his data, reboots or sleeps a machine, or changes firewall, network or power settings beyond keep-awake.
For anything else, say what is wrong and the one thing Aaron could do, and wait for him.
Grafana's Spike / Machines dashboard charts the same readings, and an alert fires if the monitor itself stops for 10 minutes.
