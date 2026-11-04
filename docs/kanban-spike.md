# kanban.spike.cute.engineer

Change 20261104-172059-233618 proposed this and change 20261104-173258-334843 landed it, with Aaron's yes to the pilot-side changes, the runner bearer route and the runners on piggys-MBP and jimbo.

## Design

Spike proxies pilot's board; it runs no board of its own. Cards stay on pilot, and pilot's local board keeps working unchanged.
Runners reach that same board through spike rather than through a WireGuard listener on pilot, so pilot opens no port and keeps `KANBAN_AUTH=off` on loopback.
Each runner long-polls the hub, so the hub never connects out to a runner.

## Landed in jimbo

- `kanban-tunnel` carries each of Caddy's connections to the board over butler's own ssh to pilot, running `nc 127.0.0.1 7420` there, the route `butler-board-relay` already takes, so pilot authorizes no new key (change 20261104-174743-421626 replaced the dedicated tunnel key, which pilot never authorized).
- `kanban-remote.nix` lets piggys-MBP and jimbo in as viewers, and passes a runner's calls (bearer token, no `Origin`, `/runner.js` and `/api/runners/(register|<id>/heartbeat|<id>/commands[/<cmd>])` alone) through to the board with `Authorization` kept, so the board's own `KANBAN_RUNNER_TOKEN` check guards them, not the device gate.
- `pilot/kanban.nix` sets `KANBAN_RUNNERS=piggys-mbp,jimbo`.
- `modules/kanban-runner` runs the runner on piggys-MBP (launchd) and jimbo's NixOS (user unit).

## Hand steps left

1. Cloudflare: DNS-only A records for `kanban.spike` and `desk.spike` pointing at `10.100.0.1`.
2. Spike: `sudo device-gate-password`.
3. Pilot: `just`, write `KANBAN_RUNNER_TOKEN=$(openssl rand -hex 32)` to `~/.config/kanban/env` (mode 600), make sure `dist/runner.js` is built (`npm run build` in `~/workspace/kanban`), and restart the board.
4. piggys-MBP: `just`, then write the same token to `~/.config/kanban/env` (mode 600).
5. jimbo: boot NixOS, set `jimboPublicKey` in spike's `wireguard.nix` from `sudo wg show wg0 public-key`, then `just` and write the token there too.
6. Test: open `https://kanban.spike.cute.engineer` from piggys-MBP, sign in, pick "piggys-mbp" under "where it runs", start a session, and watch its card.
