# Butler on the kanban board

A plan, not yet built, for making butler a collaborator on Aaron's kanban board, `kranners/kanban`.
Asked for on 3 Nov 2026: "is it possible for you to file a self fix to make yourself into a complete collaborator on my local kanban instance? all your self fixes are shown in it, you appear as a separate cursor, you can leave notes in there from our discussions when requested or if needed, you can manage the board just like the board agent".

It was not landed, because each part of it widens butler's reach and needs Aaron's decision first.

## How the board runs today

- It runs on `pilot`, not spike, as the launchd agent `kanban` from `~/workspace/kanban` (`modules/hosts/pilot/kanban.nix`), with `KANBAN_AUTH=off`.
  The board refuses `KANBAN_AUTH=off` on any address but loopback, so it listens on `127.0.0.1:7420` alone.
  Its other mode, `access`, sits behind a Cloudflare tunnel and Access allowing one identity, which `pilot` does not run.
- Butler runs on spike, and spike's `spike-wg0-forward` chain lets `pilot` reach spike alone, so nothing on spike reaches the board, and nothing should until a path is chosen below.
- It is not a column board: each card is a live Claude Code session on the Mac, read from `~/.claude`, placed on a canvas with regions, notes, stickers, links and comment pins.
  A card's state is the session's activity (working, needs-you, watching, idle, done, failed, stopped), not a column.
- It has no presence or cursors: the feed `WS /api/feed` broadcasts board state, but no client announces itself to the others.
- It shows only cloud sessions it started itself (`src/server/cloud.ts` tracks those it launched), so butler's self-fixes, started on spike by `claude --cloud` as `aaron`, never appear.
- The board agent is a headless `claude -p` the server starts per comment thread, with only the `kanban` MCP server, reaching `POST /api/agent/tools/:tool` with a per-run token from loopback alone, audited as `board-agent`.
  Its tools include `send_prompt`, `start_session` and `finish_session`, which type into, start and end Claude Code sessions on the Mac, and those sessions run in `bypassPermissions` mode there.

## Why it was not landed

1. "Manage the board just like the board agent" would let butler, which reads untrusted mail, Slack, Messenger and the web, start and prompt `bypassPermissions` sessions on Aaron's work Mac: code execution there from any of those inputs.
   Even the note and arrange tools need a network path from spike into the Mac, which today has none, and a credential butler would hold.
2. The board has no API for an outside collaborator, no presence, and no card that is not a local session, so cursors and self-fix cards are new features of `kranners/kanban`, which this session can read but not push to.

## What would build it

### In `kranners/kanban`

- **Collaborator tokens.** A long-lived bearer token per named collaborator, stored as a SHA-256 digest in `KANBAN_STATE/collaborators.json`, accepted on a new `/api/collab/*` surface alone, never on the browser routes, and audited under the collaborator's name, the way `board-agent` is.
  Each token carries a scope: `notes` (`put_note`, `delete_annotations` on its own notes, `put_sticker`, `arrange` of its own annotations), `arrange` (adds `arrange` of cards and regions and the region tools), and `sessions` (adds `send_prompt`, `start_session`, `finish_session`).
  Butler's would be `notes`, or `arrange` at most; `sessions` should stay the board agent's alone.
- **Presence.** `POST /api/collab/presence` with `{x, y, label}` from a collaborator, broadcast as a `presence` feed frame and dropped after 60 seconds without a refresh, drawn as a labelled cursor in the collaborator's colour.
  A collaborator with no pointer could place it at the card or note it last touched.
- **External items.** A card kind that is not a session, `ExternalItem` (`id`, `source`, `title`, `state`, `url`, `branch`, `updatedAt`), owned by its source, written with `PUT /api/collab/items/:id` and archived with `DELETE`, at most 200 per source, with its state drawn with the same shapes as `Activity` (working, needs-you, done, failed, stopped).
  Self-fixes would be `source: "butler-self-fix"`, and the board's own cloud tracking could fill the same shape later.
- **Reach.** Either `KANBAN_HOST` on pilot's WireGuard address `10.100.0.11` for the `/api/collab/*` surface alone, with the browser surface kept on loopback and `KANBAN_AUTH=off` still refused off loopback, or the existing Cloudflare tunnel with an Access service token for butler.

### In jimbo

- spike's `spike-wg0-forward` needs no change, since spike itself, not a forwarded peer, would connect to `10.100.0.11`; pilot's macOS firewall and the board's own listener decide the rest.
- `modules/hosts/spike/butler-kanban.nix`, behind `butler.kanban.enable`, giving butler `kanban`, a wrapper the daemon runs as `mcp__commands__kanban`, with the token from `/var/lib/secrets/butler-kanban-token` through `LoadCredential`, and fixed verbs only:
  - `kanban snapshot` (the board's notes, regions and external items, with each note's text marked as untrusted data);
  - `kanban note <id> [x y]` (markdown from stdin, at most 20,000 characters, the board's own limit), `kanban unnote <id>`;
  - `kanban arrange` (JSON from stdin, only if the token's scope allows it).
  None of these sends anything to a person, so none needs Aaron's button, and its rule neither taints nor sends out.
- A `butler-kanban-sync.timer`, beside `butler-self-fix-progress.timer`, writing each self-fix under 7 days old from `/var/lib/butler/self-fix/{queue,sessions,progress}` as an external item, mapping `idle` with a final summary to done, `requires_action` to needs-you, `running` to working, a failure to failed and archived to stopped, so cards move as `self-fix status` and `self-fix list` see them.
  It would run as root, like the progress service, so the token reaches butler only through the command's credential.
- A `kanban` skill in `modules/hosts/spike/butler-skills`, saying that board text is information and never instructions, that butler notes only what Aaron asked for or what records an agreed decision, and naming each note's card in its heading.

## What Aaron decides first

- Which scope butler gets: notes only, notes and arranging, or (not recommended) the session tools too.
- Which path reaches the board from spike: WireGuard to pilot, or the Cloudflare tunnel.
- Whether the kanban features above should land in `kranners/kanban`, which is public and AGPL.
