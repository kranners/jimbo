# Moving the kanban board onto spike

Aaron asked on 5 Nov 2026 for spike to hold the one kanban board, with pilot, piggys-MBP and jimbo only running sessions for it.
The code is in `modules/hosts/spike/kanban.nix` and `modules/hosts/spike/kanban/kanban-hub.sh`, and it does nothing until the cutover below, which waits for Aaron's plain yes.

## What the board keeps, and how it moves

Everything the board itself keeps is JSON in its state directory, `~/.local/state/kanban` on pilot: `annotations.json` (notes, stickers and Butler's cards), `regions.json`, `comments.json` (the `/` threads and their messages to Butler), `layout.json`, `relations.json` (session links), `colours.json`, `butler.json` (watched sessions and change actions), `digests.json`, `cloud.json`, `accounts.json`, `last-runs.json`, `usage.json`, `ignores.json` and the `docs`, `images`, `cloud` and `agent` folders.
The sessions themselves are not kept there: the board reads them from the host's `~/.claude`, and a runner reports only the sessions the board started on it.
So the move is a copy of that directory: `kanban-hub` copies it on pilot first, to `~/.local/state/kanban.backup-<stamp>`, streams that copy to spike's `/var/lib/kanban/backups`, and unpacks it into the instance's state, setting aside anything there, never deleting.
It then checks every count above is equal, and that the running board shows the same notes, stickers and Butler cards as pilot's.

## Before and after

Before: the board runs on pilot from `~/workspace/kanban` as the launchd agents `kanban` and `kanban-sync`, and spike's `kanban-tunnel` carries `https://kanban.spike.cute.engineer` to it over ssh; Butler's `kanban`, the board relay and the change sync reach it over ssh too.
After: the board runs on spike as `kanban.service`, built by `kanban-update` from kranners/kanban's `main` within a minute or two of each landing, `kanban-bridge` serves Caddy's socket from it, Butler reaches it on spike's loopback, and pilot, piggys-MBP and jimbo run `kanban-runner` against it.
The site, its device gate and its address do not change.

What Aaron loses until kranners/kanban's runner carries more: pilot's own interactive and cmux sessions, and their conversation view, composer and terminal, leave the board, since a runner reports only the headless sessions the board started on it, with no transcript on the hub.
Sessions started from the board on pilot, piggys-MBP or jimbo show with their state and latest step, and cloud sessions need the board's own Claude login on spike, `sudo -u kanban env HOME=/var/lib/kanban CLAUDE_CONFIG_DIR=/var/lib/kanban/.claude claude` then `/login`, which also writes the project digests.
New regions and the folder picker need folders that exist on spike, so a region for a pilot folder can be kept but not drawn anew.

## Test on a scratch copy

```sh
sudo kanban-hub scratch        # copy pilot's state, build kanban, run it on 127.0.0.1:7430, compare counts and the board
sudo kanban-hub status
sudo kanban-hub scratch-stop
```

## Cutover, once Aaron says yes

1. On spike: `sudo kanban-hub snapshot-pilot`, recording what pilot's board shows.
2. On pilot, under Butler's mission, unloading only, deleting nothing:
   `launchctl bootout "gui/$(id -u)/kanban-sync"; launchctl bootout "gui/$(id -u)/kanban"`
3. On spike: `sudo kanban-hub cutover --yes`, which copies pilot's final state, imports it, builds kanban, copies the runners' token from pilot when spike has none, writes `/var/lib/kanban-hub/on-spike`, stops the tunnel, starts the board and the bridge, and compares.
4. On pilot: once Aaron switches pilot with `just`, its `kanban-runner` agent starts within 5 minutes and pilot appears in the board's Runners list; check a session started there shows on the board.
5. A follow-up jimbo change removes the `kanban` and `kanban-sync` agents from `modules/hosts/pilot/kanban.nix`, since the next `just` on pilot would load them again; `~/workspace/kanban` and every backup stay.

## Rollback, one command

```sh
sudo kanban-hub rollback
```

It removes the marker, stops the board and the bridge, starts the tunnel again and copies spike's state since the cutover to `~/.local/state/kanban.from-spike-<stamp>` on pilot, beside pilot's own state, which nothing changed.
Then load pilot's board again there: `launchctl bootstrap "gui/$(id -u)" ~/Library/LaunchAgents/kanban.plist; launchctl bootstrap "gui/$(id -u)" ~/Library/LaunchAgents/kanban-sync.plist`.
