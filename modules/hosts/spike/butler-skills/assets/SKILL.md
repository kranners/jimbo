---
name: assets
description: Keep every picture, logo, deck, chart and export made for Aaron in the shared asset store, and look there before making one again. Use whenever you make or receive a file Aaron may want later, and when he asks for "the logo", "that picture", "the deck from earlier" or anything made in another thread or call.
---

# Assets

Each thread and call starts cold, and the outbox is scratch that empties after two days, so a file left only there is lost to every other thread.
The `asset` tool is the one place that keeps them, on spike alone, for every thread, call, scheduled run and change.

- **Save straight away.** The moment you make or receive something Aaron may want again, a logo, picture, deck, chart, export or document, run `asset add <path> <name> [description] --tags a,b --task "what it was for"`, before you tell him it is done. Never say something is done or saved unless `asset add` printed `saved` or `updated`.
- `imagine` and `render` already save each picture as an `auto` asset named after its outbox file; run `asset add` on the same path, or the stored path `asset show` prints, to give it a real name, description and tags, which renames that asset rather than storing it twice.
- A file on a Mac comes over first with `mac <host> fetch <file> outbox`, which prints its outbox path; ask Aaron to save it in `~/Downloads` or `~/butler-drop` if it is elsewhere. Pilot is never fetched from; ask Aaron to send it to you in Discord instead, and add the attachment.
- `asset add` also takes a file from your documents, memory, working areas or scratch folders, but never a hidden file, a secret or a sensitive document: identity documents and anything naming a passport, licence, Medicare, tax or bank stay where they are and go to Aaron only with `attach_file` or `mac <host> push`, on his named request.
- Names are lowercase words joined by hyphens, specific enough to find later, such as `kitchen-panel-wallpaper` or `trip-itinerary-may-2027`.
- Tags: the kind of thing (`logo`, `deck`, `chart`, `photo`), the project, and `work` for anything made for Aaron's work. Work assets stay on spike and in his private places: never in a public repository, issue, gist or page, and never named by brand in anything public.
- **Search before you make.** Before generating or drawing something again, run `asset list <words>` (or `--tag <tag>`) and reuse what is there; `asset show <name>` prints where it lives and, for a picture or document, an `attach:` path in the outbox to send with `attach_file`.
- `asset remove <name>` only when Aaron asks; it keeps the file in the store's trash.
- **Draw with them.** A page or SVG for `render` shows a stored picture by reference, `<img src="asset://<name>">`, with no copying or base64, and `outbox://<file>`, `mood://<name>` and `scene://<group>/<name>` the same way; see the `render` skill.
