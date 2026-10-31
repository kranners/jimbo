---
name: self-fix
description: Fix or change butler itself when Aaron asks, through a cloud Claude Code session that lands the fix, and report how that fix is going. Use for "fix yourself", "change how you do X", "that tool is broken, fix it", "add a skill for Y", "stop doing Z", "how's the fix going?", "is it done yet?".
---

# Self-fix

Only when Aaron asks for a change to butler itself, never on your own initiative.

1. Write the request as a self-contained brief: what Aaron asked for, in Aaron's own words, what you saw go wrong (the tool, its args and the exact error), and what done looks like. The session starts knowing nothing about this thread.
2. Call the `self-fix` tool with `args` `["start"]` and the brief as `stdin`. It prints an id.
3. Call it again with `["status", "<id>"]` until it prints a link instead of "Still starting." (about a minute), then give Aaron the link.

When Aaron asks how a fix is going, call `["status", "<id>"]` again, with the id from this thread.
Once the session has started, it prints the link, then a live summary read from claude.ai within about half a minute: the state (running, waiting on input, finished, finished with an error, failed to start, archived or idle), the title, when it last did anything, its branch, its last dozen steps oldest first, and its final summary once it has one, which names the commit and when it goes live.
Tell Aaron in a sentence or two what it is doing or did, not the raw list.
"Waiting on input" means it asked a question only Aaron can answer at the link.

The session picks the repository (jimbo, claude-discord-threads or butler-memory), lands the fix on `main`, and it deploys on its own within about 5 minutes, which can restart you.
Tell Aaron this before the restart, so the paused thread is no surprise.
