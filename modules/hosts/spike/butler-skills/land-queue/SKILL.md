---
name: land-queue
description: See and steer spike's landing queue, the deploys held back so a fix that restarts you never drops Aaron's call. Use for "what's waiting to land?", "land it now", "hold the fixes", "land them at eleven", "land when I'm quiet", "stop holding deploys", "always hold deploys", "turn the landing queue off", and when Aaron asks when a fix goes live.
---

# Landing queue

Self-fixes still land their code on `main` at once; what waits is spike's deploy of it.
A deploy that would restart you, or the speech services your calls use, waits while a call is live, and goes out on the first cue: the call quiet for 20 seconds with nobody talking, no audio playing and no turn working, the call ending, Aaron's word, a time he named, or 30 minutes after it was first held.
Once a held landing goes during a call, your own restart still waits for a quiet moment and you say "Applying an update, one moment." as always; spike itself says "A fix is about to land, sir, I'll be back in a moment." first only when the landing also restarts your speech services, and never while Aaron is mid-sentence. You rejoin the call by yourself and say which fix landed.
`/land` decides when a deploy goes out; `/restart` (or "update now", "hold off") decides when you take a restart a deploy already wants.
With no call live a released landing DMs him one line instead.
A deploy that restarts nothing a call needs goes out at once, and with no call live everything goes out as before, unless Aaron chose `always`.
A commit that follows one that failed to switch, or carries a `Land: now` line in its message, skips the queue.
A held commit that fails to build is still reported at once, by a shout or a DM, and spike keeps running the last good version.

Call the `land-queue` tool with these `args`:

- `[]` or `["status"]`: the mode, whether a call is live and how long it has been quiet, and each repository waiting, with its fixes' titles, when each landed, what it would restart and when it lands at the latest. You may read it on a call.
- `["now"]`: land everything waiting at once, or, with nothing waiting, let the next landing in the next 15 minutes go straight out. Use it when Aaron says a fix is urgent.
- `["hold"]`: hold everything until he releases it, for at most 30 minutes each.
- `["release"]` or `["when-quiet"]`: back to the quiet cue, clearing `hold`, `at` and `now`.
- `["at", "23:00"]`: land what is waiting at that time, Melbourne time, tomorrow if it has passed; it outlasts the 30 minute limit.
- `["on"]`, the default: hold only while a call is live. `["off"]`: never hold. `["always"]`: hold even with no call, until `now`, a time or 30 minutes.

Aaron can type the same as `/land`, such as `/land at 23:00` or `/land off`, and the mode is kept across restarts.
Answer him in a sentence: what is waiting and when it goes, not the raw list.
