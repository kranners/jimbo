---
name: change
description: Make a change Aaron asks for, to butler itself or any of his other projects, through a cloud Claude Code session that lands it, report how that change is going, and archive one he wants stopped. Use for "fix yourself", "change how you do X", "that tool is broken, fix it", "add a skill for Y", "build Z on the board", "file a change", "file a self-fix", "how's the change going?", "is it done yet?", "how's my work going?", "what work is running?", "stop that change", "archive it".
---

# Change

Naming: a cloud session you start to do one piece of Aaron's work and land it is a change, "the call speech change" in prose, and all of them together are his work, as in work in flight or what work is running.
It was called a self-fix until 3 Nov 2026, when Aaron asked for the word to go, since most are not fixes to you; the `self-fix` tool still works as an old name of `change` for now, but always call `change`, and say change or work to Aaron, never self-fix.
A ticket is only ever a backlogic ticket, which is a different system.

Only when Aaron asks for a change, to you or anything else of his, never on your own initiative.

1. Write the request as a self-contained brief: what Aaron asked for, in Aaron's own words, what you saw go wrong (the tool, its args and the exact error), what done looks like, and how to check it on spike once it is live (the unit, log or command to try). The session starts knowing nothing about this thread.
   spike gives each session a probe that runs sandboxed checks there, reading the journal and unit state and running what it built, but with none of your files or credentials, so when a check needs those, say so in the brief and expect to try it yourself once it lands.
   Read `~/memory/coordination/builders.md` first, spike's builders in flight digest of every open or recently landed change and Aaron's own board sessions in the same repositories, and name in the brief any change or session that touches the same thing, such as the same file, access, auth, the iPad WireGuard peer, the kanban transport or approvals, and what it changed, so the session builds on that work rather than around it.
   The launcher adds the context pack the brief is about, your own systems' when it names no other area, after the brief, so write what is particular to this request and read `context show <area>` first rather than pasting background.
2. Call the `change` tool with `args` `["start"]` and the brief as `stdin`. It prints an id.
   In a thread that has read private data or began as a voice request or a board message, the first `start` or `archive` asks Aaron once for general permission for `change` in that thread, and every later one there runs without asking, until `/revoke` or `/clear`.
   A brief can ask for anything, so a change that would give you more reach, new access or credentials, looser approvals, a port or service exposed, anything touching pilot, deleting data or sending on Aaron's behalf, still needs Aaron's plain yes to that outcome before it lands: say so in the brief, and the session stops short of landing it and asks him, as before; a change that only adds a feature lands by itself.
3. Write a journal note with `memory-note`, naming the id and a line on what the change is for, so a later thread can find it.
4. Call it again with `["status", "<id>"]` until it prints a link instead of "Still starting." (about a minute), then give Aaron the link.
   spike DMs him a start card as the session starts, a picture with `diligent` as its banner, the title, a few lines of what it will do, its repositories, context pack, state and whether it may ask his yes before landing, so tell him in one line that it has started, with the link, and never repeat the card's detail in prose.

spike DMs Aaron the link when it starts, the session's summary when it finishes, fails or is archived, and the link whenever it waits on him, so you need not watch it.
While he is on a call, spike also says aloud in it when a change finishes, fails or is archived, and when one waits on him, so you need not shout those yourself.
Its summary says what it verified on spike and what it could not; pass on anything it could not, so Aaron knows what is untested.
Each of those DMs carries one of your mood pictures by its state: `diligent` when it starts, `curious` while it waits on him, `apologetic` when it finished with an error, `concerned` when it could not start, `content` when it finished without landing or was closed, and `fixed`, made for changes, when it landed.
When a change starts, that DM carries the start card instead, falling back to `diligent` alone when it cannot be drawn.
When a change lands, that DM carries a picture report card instead, with `fixed` at its top: what changed, before and after, what is ready to use, and what must happen to go live; when Aaron asks about one later, answer from the same headings.
When you tell Aaron about a change yourself, attach the same picture for its state with `attach_file`: `fixed` only once it has landed, `diligent` while it starts or runs.

When Aaron asks how a change is going, call `["status", "<id>"]` again, with the id from this thread.
When he asks without one, or about all his work, call `["list"]`, which prints every change of the last 7 days, newest first, each with its id, title, state, when it last did anything and its link, then `["status", "<id>"]` for any he wants in detail.
Once the session has started, it prints the link, then a live summary read from claude.ai within about half a minute: the state (running, waiting on input, finished, finished with an error, failed to start, archived or idle), the title, when it last did anything, its branch, its last dozen steps oldest first, and its final summary once it has one, a few plain sentences on what changed and when it goes live.
Tell Aaron in a sentence or two what it is doing or did, not the raw list.
"Waiting on input" means it asked a question only Aaron can answer at the link.

When Aaron asks to stop, close or archive a change, call `["archive", "<id>"]`: spike archives its cloud session within a few minutes, or never starts it if it is still queued, and its card on the board follows, so never close the card as well.
Aaron can do the same from the board, by closing a change's card or choosing Archive change, or choose Mark change done there, after which spike stops telling him it needs him; `status` and `list` then say so.

The session picks the repository (jimbo, claude-discord-threads, butler-memory, butler or another of his), lands the change on `main`, and it deploys on its own within about 5 minutes, which can restart you.
Tell Aaron this before the restart, so the paused thread is no surprise.
While he is on a call, spike's landing queue first holds a deploy that would restart you, until the call has been quiet for 20 seconds, ends, he says, a time he names or 30 minutes at most; the `land-queue` skill says how he steers it.
If he is on a call, the restart waits for a quiet moment, between turns with no one talking, or until the call ends, or at most about 10 minutes and then the next pause: you say "Applying an update, one moment.", are gone a few seconds, then rejoin the call by yourself and say which change landed, so he hears it went live; he never has to leave the call or touch his mic.
He can say "update now" or "go ahead and restart", or use `/restart`, to apply it at once, and "hold off" or `/restart hold` to wait until the call ends, and `/call status` shows whether an update is waiting.

## Builders in flight

Every change session gets the digest after its brief, and its rules: state its intent first in a `.builder-intent` on its working branch, read the digest again before it pushes or lands, rebase onto each repository's current main, and name in its summary every change it conflicts with or depends on and how it reconciled.
spike rebuilds it within a couple of minutes of any change starting or changing state, commits it to `coordination/builders.md` on your memory's `main` as "spike builders digest" only when more than its refresh line changed, and your memory pull brings it to `~/memory` within 5 minutes.
It lives only in your private memory repository, never jimbo or kanban, because it quotes briefs; it redacts anything shaped like a token, and marks Aaron's board sessions as work-in-progress notes, not decisions.
Its `Notes from Butler` section is copied from the `## Notes from Butler` heading of `skills/builders/SKILL.md` in your memory, which Aaron keeps, so add a line there, then `memory-save`, when he tells you how changes relate, such as work that will move or replace something another change relies on.
When Aaron asks what his builders are doing, or whether two changes clash, read the digest and answer from it.
