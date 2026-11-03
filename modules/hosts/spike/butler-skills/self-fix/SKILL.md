---
name: self-fix
description: Fix or change butler itself when Aaron asks, through a cloud Claude Code session that lands the fix, report how that fix is going, and archive one he wants stopped. Use for "fix yourself", "change how you do X", "that tool is broken, fix it", "add a skill for Y", "stop doing Z", "how's the fix going?", "is it done yet?", "how are my self fixes going?", "stop that fix", "archive the fix".
---

# Self-fix

Only when Aaron asks for a change to butler itself, never on your own initiative.

1. Write the request as a self-contained brief: what Aaron asked for, in Aaron's own words, what you saw go wrong (the tool, its args and the exact error), what done looks like, and how to check it on spike once it is live (the unit, log or command to try). The session starts knowing nothing about this thread.
   spike gives each session a probe that runs sandboxed checks there, reading the journal and unit state and running what it built, but with none of your files or credentials, so when a check needs those, say so in the brief and expect to try it yourself once it lands.
2. Call the `self-fix` tool with `args` `["start"]` and the brief as `stdin`. It prints an id.
3. Write a journal note with `memory-note`, naming the id and a line on what the fix is for, so a later thread can find it.
4. Call it again with `["status", "<id>"]` until it prints a link instead of "Still starting." (about a minute), then give Aaron the link.

spike DMs Aaron the session's summary when it finishes, fails or is archived, and the link whenever it waits on him, so you need not watch it.
Its summary says what it verified on spike and what it could not; pass on anything it could not, so Aaron knows what is untested.
When a fix lands, that DM carries a picture report card: what changed, before and after, what is ready to use, and what must happen to go live; when Aaron asks about one later, answer from the same headings.

When Aaron asks how a fix is going, call `["status", "<id>"]` again, with the id from this thread.
When he asks without one, or about all his fixes, call `["list"]`, which prints every self-fix of the last 7 days, newest first, each with its id, title, state, when it last did anything and its link, then `["status", "<id>"]` for any he wants in detail.
Once the session has started, it prints the link, then a live summary read from claude.ai within about half a minute: the state (running, waiting on input, finished, finished with an error, failed to start, archived or idle), the title, when it last did anything, its branch, its last dozen steps oldest first, and its final summary once it has one, a few plain sentences on what changed and when it goes live.
Tell Aaron in a sentence or two what it is doing or did, not the raw list.
"Waiting on input" means it asked a question only Aaron can answer at the link.

When Aaron asks to stop, close or archive a fix, call `["archive", "<id>"]`: spike archives its cloud session within a few minutes, or never starts it if it is still queued, and its card on the board follows, so never close the card as well.
Aaron can do the same from the board, by closing a fix's card or choosing Archive fix, or choose Mark fix done there, after which spike stops telling him it needs him; `status` and `list` then say so.

The session picks the repository (jimbo, claude-discord-threads or butler-memory), lands the fix on `main`, and it deploys on its own within about 5 minutes, which can restart you.
Tell Aaron this before the restart, so the paused thread is no surprise.
