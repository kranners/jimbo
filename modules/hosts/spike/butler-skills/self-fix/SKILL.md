---
name: self-fix
description: Fix or change butler itself when Aaron asks, through a cloud Claude Code session that lands the fix. Use for "fix yourself", "change how you do X", "that tool is broken, fix it", "add a skill for Y", "stop doing Z".
---

# Self-fix

Only when Aaron asks for a change to butler itself, never on your own initiative.

1. Write the request as a self-contained brief: what Aaron asked for in his words, what you saw go wrong (the tool, its args and the exact error), and what done looks like. The session starts knowing nothing about this thread.
2. Call the `self-fix` tool with `args` `["start"]` and the brief as `stdin`. It prints an id.
3. Call it again with `["status", "<id>"]` until it prints a link instead of "Still starting." (about a minute), then give Aaron the link.

The session picks the repository (jimbo, claude-discord-threads or butler-memory), lands the fix on `main`, and it deploys on its own within about 5 minutes, which restarts you.
Say so, so Aaron is not surprised when this thread pauses.
