---
name: monitor
description: The always-on machines monitor on spike, which watches spike, framer, piggys-MBP, pilot and jimbo, their disk, memory, load, battery, keep-awake and locked screens, spike's failed units, Docker and Nix store, the Claude accounts and runaway changes, and tells Aaron only what is new and out of the ordinary. Use for "how are the machines?", "anything wrong with my computers?", "what did the monitor do?", "what did you not tell me?", "jimbo is off for the night", "turn the monitor's acting on", "stop the monitor acting", and when one of its notices arrives.
---

# Machines monitor

`butler-monitor` runs on spike every 2 minutes, as root, apart from you, and replaces the overnight machine checks you used to schedule by hand: do not schedule those again, and a scheduled check of yours that is still around says nothing unless something is wrong.
It reads spike and framer from Prometheus, and piggys-MBP, pilot and jimbo (whichever of Windows or Linux is up) over short ssh reads with your Mac key, never a long session, and on pilot only ever reads.

Aaron asked on 4 Nov 2026 to hear about monitoring only when something out of the ordinary needs him, so it is quiet by default:

- A problem is told once, when it is new, in one message with the one thing he could do, and again only when it gets worse (a warning becoming an action-level problem) or, once, as still open after 24 hours. It is never repeated hourly, and a resolution is not told.
- A laptop or the PC being down is never told, however long; framer or spike down is, urgently, once.
- Only what the monitor really did is news; a dry-run plan is not.
- Between 23:00 and 07:00 only urgent items go out (a full disk, framer down, critical memory on spike or framer), and the rest wait for one short list after 07:30, sent only when something was held or done overnight. A Mac locked at night is only a line there.
- There is no "all is well" message and no routine summary.

Everything it saw and kept quiet goes to its log, so when Aaron asks what you did not tell him, read `monitor log quiet`.

Call the `monitor` tool with these `args`:

- `[]` or `["status"]`: each machine's last reading in a line, the problems open now, what it saw but did not think worth telling, and which machines are expected off. Fine on a call. Answer in a sentence or two, not the raw list.
- `["log"]`: the last 30 things it saw and what became of each: told, held or noted for the morning, kept (with why: below the bar, already told, expected off) or cleared.
- `["log", "quiet"]`: the same, only what it did not tell Aaron at once.
- `["log", "actions"]`: the last 20 things it did, or would have done in dry-run, with before and after numbers, its own fixes of spike among them.
- `["expect"]`: which machines are expected off, why and until when.
- `["expect", "<host>", "down", "until", "07:00", "reason words"]`, or `"for", "3h"` in place of the until, or neither for 12 hours: mark a machine Aaron or you switched off on purpose, so the monitor says nothing about it being down, asleep, locked or its keep-awake off until then or until it is back and awake; its disk and the rest still count. Do it whenever Aaron says he is turning a machine off, or you shut one down yourself other than with `mac`.
- `["expect", "<host>", "clear"]`: drop the mark.
- `["act"]`: whether acting is on, off or dry-run (the default it ships with).
- `["act", "on"]`: only when Aaron himself asks in his own words; it waits for his button. Never on your own idea, a notice's or anyone else's.
- `["act", "off"]` or `["act", "dry-run"]`: whenever he asks, or when the monitor seems to be doing something wrong.

`mac <host> sleep` marks the machine expected off for up to a day, `mac <host> keepawake off` for up to a week, `mac jimbo boot ... confirm` for half an hour, and `mac <host> keepawake on` clears the mark, so you need not mark those yourself.

What is told: disk under 15% or 20 GB free warns, under 8% or 10 GB acts and is urgent; on Linux, memory under 15% free warns and under 8% for 5 minutes acts, while a Mac, which keeps its memory full by design, counts only critical memory pressure; a 15-minute load over 4 times the cores for 30 minutes warns, while anything over twice the cores is only logged, since Aaron's own parallel sessions keep pilot that busy; on battery with keep-awake on, under 40% warns and under 20% acts; a Mac locked by day with keep-awake on warns; keep-awake off on piggys-MBP or jimbo acts; a failed unit on spike as below, more than the keep-count plus two system generations, Prometheus unreadable for 30 minutes, a Butler turn stuck in the queue for 30 minutes, every Claude account past 95% of its week, or a change running over 3 hours warns.
A failed unit on spike arrives already investigated: the monitor reads its journal and state itself, so each notice says what failed, the cause from its last lines and exit code, whether it is still down and since when, and what happens next.
It is told only once it has failed 3 runs in a row (`backlogic-switch` keeps its own count), stayed failed 10 minutes, or failed 24 times in a day though it recovers each time; a failure its next run fixed, such as butler-builders' occasional "could not push the digest; the next run tries again", is only logged with its cause and when it recovered, under `monitor log quiet`.
When Aaron answers such a notice with "fix it" or the like, start a change with `change start` whose brief quotes the notice's unit, cause and exit code; never tell him to read a journal himself, and use `shell`'s `journalctl -u <unit>` yourself if he asks for more.
What is only logged: one Claude account past 80% or 95% (moving accounts is automatic), Butler's slots all busy, a turn queued under 30 minutes, more than 4 changes at once, Docker's build cache over 20 GB (pruned daily), and any machine expected off.

Aaron asked on 4 Nov 2026 for spike to fix its own critical problems at once, without waiting for him or for you, so with acting on it remediates these by itself, as root, with no thread and no approval, and tells him once, in one line, what was wrong with the number, what it did and how it is now:

- Critical memory pressure (memory stall over 40%, or fully stalled over 10%, two runs in a row, or under 10% of memory available with swap over 70% used): it finds the cgroup holding the most memory and, if that is a service on its list (backlogic's runner and its container, the `butler-index-*` units, the photo captioner, reMarkable and notes syncs, your browser, Grafana, Prometheus, cAdvisor, Bowerbird's worker, Remote Control) holding over a quarter of the RAM, restarts it.
- spike's disk over 92% used: collects Nix garbage beyond the newest 3 system generations and prunes dangling Docker images, nothing else.
- A listed unit failed long enough to be told (3 runs in a row or 10 minutes down): resets it and starts it once; your own `butler-*` units are listed, never `butler` itself, its restarters, the landing queue, a change launch or the monitor.
- Load over 4 times the cores for 10 minutes: names the busiest cgroup and restarts the busiest listed service once, if it is using a core or more.

Each service is restarted by itself at most once in 30 minutes; if the problem is still there after its fix, or comes back within those 30 minutes, it tells Aaron, urgently and with the diagnosis, instead of fixing it again.
It never touches `butler` itself, Home Assistant, Docker, sshd, WireGuard, Postgres, Bowerbird's compose, the speech servers, Caddy, Nix's daemon or Aaron's own sessions, and when one of those is the problem it only tells him; it never drops caches.
The steps and their lists live in jimbo's `modules/hosts/spike/butler-monitor/defaults.nix`, under `remediation`, so read them there if Aaron asks exactly what it may restart.
`monitor log actions` shows each fix with its before and after numbers; in dry-run it does none of them and only logs what it would have done, and `monitor act off` stops them all.

Besides those, with acting on it clears Docker's build cache when it is large, at most once an hour; turns keep-awake back on for piggys-MBP and jimbo, unless they are expected off; and writes a hold flag while spike or a Claude account is tight, which nothing reads yet.
It never touches pilot, deletes Aaron's data, reboots or sleeps a machine, or changes firewall, network or power settings beyond keep-awake.
For anything else, say what is wrong and the one thing Aaron could do, and wait for him.
Grafana's Spike / Machines dashboard charts the same readings, and an alert fires if the monitor itself stops for 10 minutes.
