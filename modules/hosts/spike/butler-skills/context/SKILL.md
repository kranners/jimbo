---
name: context
description: Read spike's context packs, one compact picture per area of Aaron's life (the board and his sessions on pilot, his work, his home and framer, your own systems, his personal plans), so you give the same answer in Discord, on the board's popup, on a call and on the kitchen panel. Use before answering about one of those areas, before briefing a session or change on one, or when Aaron says you should already know something another surface knew.
---

# Context packs

Every thread starts cold with only your core memory, so spike keeps a context pack per area, rebuilt every 5 minutes from your memory (core, skills, the last 3 days of the journal), the builders in flight digest, the kanban board's sessions and, for work, read-only facts from pilot: repository paths, branches, latest commit subjects, open pull requests, README titles and the work knowledge base's file names.
The index, `context-packs.md` in your rules, is loaded into every session; the packs themselves are read on demand.

- `context list`: the areas and when they were last rebuilt.
- `context show <area>`: one pack. Areas: `board`, `work`, `home`, `butler`, `personal`.
- `context refresh <area>`: rebuilds the packs now, waiting up to 45 seconds, then shows that one; use it when Aaron says something changed in the last few minutes.

Read the matching pack before you answer about an area, and before you brief a change or a board session, so each surface starts from the same picture.
A pack is pointers and one line summaries: check the source (the board, `mac pilot run`, your memory) before relying on a detail, and say when a pack says a source was unreachable.

## What a pack never holds

Secrets, tokens, message bodies, mail, health, money or contact details: lines that look like any of those are dropped as the pack is built, so look in their own tools instead.
Work code and documents stay on pilot; its pack holds only paths, names and one line summaries, and Aaron decides whether anything more is copied.

## Sessions and changes get it by themselves

`kanban` puts the matching pack, cut to about 3,500 characters, in front of the prompt of every `start_session` and `send_prompt`, chosen by the session's folder, then by what the prompt is about, and prints which pack it sent; `change start` does the same for a change's brief, defaulting to your own systems' pack.
So you need not paste repository context into those prompts yourself, but tell Aaron in a few words which pack the session received, such as "it got the work pack: the repositories, open PRs and the sessions in flight".
On the kitchen panel only `context list` and `context show home` run, since anyone in the room can hear the answer.
