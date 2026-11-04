# kanban.spike.cute.engineer: proposal, not landed

Change 20261104-172059-233618 stopped here because every way to finish it changes pilot or adds an auth path, both of which the brief reserves for Aaron.

## Where things stand on spike

- `kanban-remote.nix` already serves `kanban.spike.cute.engineer` behind the device gate, proxying through `kanban-tunnel.service` to pilot's loopback `127.0.0.1:7420`, so there is one board, pilot's, and nothing to sync or lose.
- The tunnel stays off because `kanban-remote-key.nix` is `null`: spike generated the key (`kanban-tunnel-key` ran on 3 Nov), but its public half has never been copied in.
- `device-gate` is inactive, which means `/var/lib/secrets/device-gate-password` was never written, so every gated site answers 502.
- Public DNS has no record for `kanban.spike.cute.engineer` or `desk.spike.cute.engineer` (NXDOMAIN), while `life`, `grafana` and `backlogic` resolve to `10.100.0.1`.

## Design

Spike proxies pilot's board; it runs no board of its own. Cards stay on pilot, and pilot's local board keeps working unchanged.
Runners reach that same board through spike rather than through a WireGuard listener on pilot, so pilot opens no port and keeps `KANBAN_AUTH=off` on loopback.
Each runner long-polls the hub, so the hub never connects out to a runner.

## Steps, in order

1. Aaron, in Cloudflare: add DNS-only A records for `kanban.spike` and `desk.spike` pointing at `10.100.0.1`.
2. Aaron, on spike: run `sudo device-gate-password`.
3. Aaron, on spike: run `sudo cat /var/lib/kanban-tunnel/id_ed25519.pub` and put the output in `modules/hosts/spike/kanban-remote-key.nix`.
   **This changes pilot**: its next `just` authorizes the key (`from="10.100.0.1",restrict,permitopen="127.0.0.1:7420"`).
4. **New auth path, needs Aaron's yes:** a Caddy matcher in `kanban-remote.nix` that sends, from the `piggys-MBP` and `jimbo` peers only, requests that carry `Authorization: Bearer` and no `Origin`, for `/runner.js` and `/api/runners/(register|<id>/heartbeat|<id>/commands[/<cmd>])` alone, through to the board with the `Authorization` header kept and `Cf-Connecting-Ip` set.
   The board's own `KANBAN_RUNNER_TOKEN` check then guards these requests, not the device gate.
   Add `piggys-MBP` and `jimbo` to that file's `viewers` too.
5. **Changes pilot:** write `KANBAN_RUNNER_TOKEN=$(openssl rand -hex 32)` to `~/.config/kanban/env` (mode 600) on pilot, add `KANBAN_RUNNERS = "piggys-mbp,jimbo"` to `launchd.agents.kanban` in `modules/hosts/pilot/kanban.nix`, then restart the board.
6. Write the same token to `~/.config/kanban/env` on piggys-MBP and on jimbo.
   `modules/kanban-runner` (on this branch) then runs the runner as a launchd agent or user unit, fetching `/runner.js` from the hub.
   Jimbo also needs `jimboPublicKey` set in spike's `wireguard.nix` before it can reach spike at all.
7. Test: open `https://kanban.spike.cute.engineer` from piggys-MBP, sign in, pick "piggys-mbp" under "where it runs", start a session, and watch its card.
