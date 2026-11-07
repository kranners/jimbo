---
name: integrations
description: Read the live integration check, spike's one read-only call per integration every 6 hours with the real credentials, and ask for a fresh one. Use for "are my integrations working?", "is Slack/Outlook/Up/Garmin still connected?", "what's broken?", "what can't you test?", "check everything now", before relying on an integration you have not used lately, and when its alert arrives.
---

# Integrations

`butler-integration-check` runs on spike as you, apart from the daemon, every 6 hours, 4 minutes after you start (so a landing that broke something is caught), and when you call `integrations run`.
It makes one cheap read per integration with the real credential (an IMAP list, `auth.test`, a ping, a token refresh or a status file a sync already writes) and classes each as `PASS`, `WARN` (degraded, rate limited, something stale, or a credential expiring within 14 days), `FAIL` (with a one-line cause and the fix), `UNSET` (not connected: Aaron has never logged it in, never told) or `OFF` (not enabled here).
It never sends, posts, pays or changes anything: the writers (`mail-send`, `slack-send`, `messenger-send`, calendar and reminders writes, `hevy routine apply`, `home call`) are checked only for their approval gate in the command manifest, never run.
Aaron hears from it only when a check newly fails or a credential will expire within 14 days, in one DM naming what and the fix; a known open failure is not told again, and one that clears and comes back is.

Call the `integrations` tool with these `args`:

- `[]` or `["status"]`: every check's last result, one line each. Fine on a call; say it in a sentence or two, not the list.
- `["failing"]`: only the failing and warning ones, with their fixes.
- `["show", "<id>"]`: one check, and when its credential expires if known.
- `["untested"]`: the commands with no live check and why (local files, spools, the clock).
- `["run"]`: a fresh check now, waiting up to 50 seconds (if it says it is still running, `status` a minute later); use it after Aaron says he has fixed something, rather than guessing.

For how to read a failure and which fix to give Aaron, read your memory's `integration-check` skill.
The results file is `/var/lib/butler-audit/integrations.json`; `monitor status` carries its one-line summary too.
