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
- 2026-10-03: `bowerbird-worker` stops with `KillMode=mixed`, so systemd signals the worker alone and it finishes its running children, and `TimeoutStopSec=35min`, five minutes past the worker's own 30 minute cap on that wait.
- 2026-10-03: The Claude statusline reads plan limits live from the usage endpoint, adds the weekly and Fable limits, redraws every 30 s, and splits into three lines of plain bars.
- 2026-10-03: GitHub Actions deploys Bowerbird to spike: the `github-actions` WireGuard peer at `10.100.0.3` logs in as `aaron` with a key forced to run `/srv/bowerbird/bin/deploy`.
- 2026-10-04: spike runs PostgreSQL 18 on port 5433 for Bowerbird's branch databases, open on the LAN and WireGuard, and `bowerbird-template` clones production into `bowerbird_template` at 03:30.
- 2026-10-04: The branch database Postgres accepts `bowerbird` from any subnet spike is on, so `spike.local`'s IPv6 addresses connect too.
- 2026-10-04: spike appends `modules/hosts/spike/CLAUDE.md` to the personal `CLAUDE.md`, so every Claude Code session there knows it is on production and how the host is run.
- 2026-10-04: spike runs the workaholic gate as the `workaholic` user every 15 minutes from `/srv/workaholic`.
- 2026-10-04: spike runs workaholic's runner, which claims and works one issue per run, instead of its gate alone.
- 2026-10-04: workaholic's sessions run their commands in bash, since the `workaholic` user's shell is `nologin`.
