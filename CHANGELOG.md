# Changelog

- 2026-10-03: The landing workflow moves into the personal `CLAUDE.md`, and each landed change appends one line here.
- 2026-10-03: spike runs `discord-threads.service`, giving each Discord thread its own Claude Code session through the Nix-managed `claude`.
- 2026-10-03: Claude Code enables experimental agent teams through `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` in the shared `settings.json`.
- 2026-10-03: claude-discord-threads moves to a private repository that spike pulls with a read-only deploy key, and `/done` cleans up a thread's worktree.
- 2026-10-03: OpenClaw is retired from spike; discord-threads replaces it.
- 2026-10-03: spike runs Bowerbird: the `bowerbird` user, Compose, Xvfb, remote view, worker and nightly backup units from `/srv/bowerbird`, with Grafana moved to `:3001`.
- 2026-10-03: Give the Bowerbird worker procps, since it measures its memory with ps.
- 2026-10-03: The Bowerbird remote view waits for the display before starting x11vnc, and restarts whenever x11vnc exits.
- 2026-10-03: spike's system path carries `nodejs_24`, the worker's Node, so `npm ci` works for `aaron`, and the Bowerbird deploy command is `ssh aaron@spike.local /srv/bowerbird/bin/deploy`.
