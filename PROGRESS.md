# issue-154: VNC into framer via a fixed domain

## Done

- Added `modules/hosts/spike/framer-vnc.nix`: a Caddy virtual host on spike,
  `https://vnc.framer.cute.engineer`, reverse-proxying to framer's own wg0
  address (`10.100.0.5:6080`), since Caddy runs on spike and framer's noVNC
  bridge does not. Imported it from `modules/hosts/spike/default.nix`.
- No firewall change needed on framer: `6080` is already open on `wg0`
  (`modules/kiosk/default.nix`), which is how spike's Caddy reaches it.
- Documented the new domain in `.claude/CLAUDE.md`, beside the existing
  noVNC/wayvnc bullet in the framer section and the DNS-hiding bullet in
  spike's Caddy bullet.
- `nix flake check --show-trace` passes (via `/run/current-system/sw/bin/nix`,
  not on `PATH` in this worktree's shell).

## Design decision worth flagging to Aaron

The issue's body suggested gating the new virtual host with `forward_auth`,
citing Bowerbird's `/vnc/*` pattern. Bowerbird's `forward_auth` checks the
portal app's own login session (`GET /api/auth/ok`, see
`docs/tickets/bowerbird-37.md`) — there is no equivalent login app for
framer's kiosk to forward_auth against. I followed Grafana's simpler model
instead (plain `reverse_proxy`, no app-level gate), since:

- wayvnc already has no VNC password and is already reachable to every
  WireGuard peer directly on `5900`/`6080` today; fronting it with Caddy on a
  fixed domain changes nothing about who can reach it, only how (TLS + a
  name instead of the raw IP and an HTTP-only noVNC bridge).
- Grafana follows exactly this shape: reverse-proxied over the same wg0
  boundary with no `forward_auth`, relying on Grafana's own login instead,
  which framer's kiosk has no equivalent of.

Flagged this to Aaron in the report; if he wants an extra gate (e.g. a wayvnc
VNC password, or Caddy `basic_auth`), that's a follow-up, not blocking.

## Remaining (Aaron only)

- Create the DNS-only A record `vnc.framer.cute.engineer` → `10.100.0.1` in
  Cloudflare (same as `grafana.spike.cute.engineer` and
  `app.bowerbird.cute.engineer`).
- After deploying (`git pull && just` on spike): confirm
  `journalctl -u caddy` obtains the certificate, and that
  `https://vnc.framer.cute.engineer` opens noVNC over WireGuard.

## Next step if resuming

Nothing left to implement; branch is pushed and ready for review. If Aaron
asks for an auth gate, add it as a follow-up commit (likely a wayvnc RFB
password file, written by hand like the other spike/framer secrets, rather
than a new forward_auth backend service).
