---
name: butler
description: Work as or with Butler, Aaron's personal assistant on spike - read and add to Butler's memory (who Aaron is, his routines, plans and journal), and message Aaron on Discord through Butler. Use when Aaron says "butler", "use butler", "ask butler", "tell me via butler", "let me know on Discord", "tell me on Discord", "let me know when it's done", or asks what Butler knows or remembers.
---

# Butler

Butler is Aaron's personal assistant, a Discord bot running as `butler.service` on spike.
This skill gives a session two of Butler's powers: its memory, and a way to message Aaron.

## Message Aaron

`send` beside this file makes Butler send Aaron a Discord DM, from any of his machines:

```sh
~/.claude/skills/butler/send 'The backup finished: 42 GB, no errors.'
~/.claude/skills/butler/send 'Here is the chart you asked for.' chart.png report.pdf
```

On spike it runs `butler-notify`; elsewhere it copies the files to spike and runs it over SSH, at `10.100.0.1` over WireGuard or `spike.local` at home (`BUTLER_HOST` overrides).
It prints `Queued notice <id>`, and Butler sends it within 5 seconds; `journalctl -u butler | grep 'sent a notice'` on spike confirms delivery.
At most 10 files, each under 25 MB.
Aaron's reply to the DM goes to Butler, not to this session.

Message Aaron when he asked to be told, when long work he is waiting on finishes or fails, or when you are blocked on him and he is away.
Say what happened and what, if anything, he needs to do, in a few lines he can read on a phone.
Send one message per event, never a stream of progress.

## Butler's memory

The memory is the private repository `git@github.com:kranners/butler-memory.git`, which Butler pulls every 5 minutes; its `README.md` says what each directory holds.
Clone it to `~/workspace/butler-memory`, or `git pull --rebase` it there if it exists, before reading.

- `core/*.md` is who Aaron is and how Butler works: read all of it before acting for Aaron.
- `journal/YYYY-MM-DD.md` is the dated record of what happened; search it with Grep when asked what happened before.
- `skills/` holds Butler's skills, and `history/` long reference material.

To remember something for Butler, append a `## HH:MM` note to today's journal, or fix `core` when a lasting fact changed, then run `scripts/check.sh`, commit and push to `main`.
The repository is personal: keep it to Aaron's own life, and never write secrets, passwords or codes there.
