# SPIKE:

This machine is spike, the always-on NixOS home server that runs Bowerbird in production and doubles as a home lab, so every action here lands on production.
Its whole configuration is the `spike` host of the flake in `~/workspace/jimbo`, whose `.claude/CLAUDE.md` describes each service in detail and whose `modules/hosts/spike/` holds their modules; Bowerbird's own side is in `/srv/bowerbird/docs/spike.md`.
The system changes only through jimbo: a branch lands on its `main`, then `git pull && just` in `~/workspace/jimbo` switches to it, and anything set imperatively is lost or ignored by the next switch.
`just` stages and builds whatever sits in `~/workspace/jimbo`, so that checkout stays clean on `main` and work happens in worktrees.
`sudo` asks for no password, so nothing stands between a mistaken command and the live system.
`/srv/bowerbird` is Bowerbird's production checkout, which `bin/deploy` updates on every push to its `main`; checking out another branch there pauses deploys until `main` is checked out again.
`~/workspace/bowerbird` is a separate development checkout, and its branch databases live on the `postgresql` unit on `:5433`, beside `bowerbird_template`, which `bowerbird-template` clones from production at 03:30.
`bowerbird-compose` runs production Postgres on `127.0.0.1:5432` and the portal on `:3000` in Docker, and `bowerbird-display`, `bowerbird-remote-view` (noVNC on `:6080`) and `bowerbird-worker` run as the `bowerbird` user with state in `/var/lib/bowerbird`.
`bowerbird-backup` dumps production into `/var/lib/bowerbird-backups` at 03:00.
Grafana on `:3001` charts Prometheus on `:9090`, which scrapes node_exporter and cAdvisor.
spike is `spike.local` on the LAN, `10.100.0.1` on WireGuard `wg0`, and `spike.cute.engineer` publicly, where WireGuard listens on UDP `51820`.
Claude Code runs here as `claude-remote-control`, serving `~/workspace` to claude.ai/code as `spike`, and as `discord-threads`, a session per Discord thread from the live checkout `~/workspace/claude-discord-threads`, so restarting either, or a switch that changes `claude-code`, ends the sessions it hosts.
`workaholic.timer` runs `workaholic` from `/srv/workaholic` as the `workaholic` user every 15 minutes, working GitHub issues within spare compute and Claude Max usage.
Secrets are written by hand and never printed, committed or sent anywhere: `/srv/bowerbird/.env`, `~/.claude/.credentials.json`, `~/.claude/channels/discord/.env`, `~/.ssh/claude-discord-threads-deploy`, `/var/lib/workaholic/.config/workaholic/claude-token`, `/var/lib/secrets/` and `/var/lib/wireguard/private`.
It has 8 threads, 15 GiB of memory and a 233 GB NVMe disk, never sleeps, and reboots itself through a hardware watchdog when it hangs and 10 s after a kernel panic.
