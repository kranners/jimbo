# Remote OpenClaw on jimbo

Goal: drive jimbo from a remote device, potentially outside the local network,
through an OpenClaw chat connector (Discord), running jobs against either cloud
models or the locally hosted LLM, with a small amount of browser automation.

## Machine facts

Verified on jimbo, not assumed:

- Ethernet `enp42s0` reports `NO-CARRIER`; no cable is attached. Only the WiFi
  interface `wlo1` (iwlwifi) is up.
- `wlo1` advertises WoWLAN support including "wake up on magic packet".
- Available sleep states are `freeze mem disk`, so both S3 and hibernate work.
- GPU is a Radeon RX 6700 XT (PCI ID `1002:73bf`) with 16 GiB of VRAM. CPU is a
  Ryzen 7 5800X3D. System RAM is 15 GiB, which is the tightest resource here.
- No user has lingering enabled, Tailscale is not installed, and OpenClaw is not
  installed. `modules/zsh` already puts `~/.openclaw/bin` on `PATH`.
- `pkgs.openclaw` exists in nixpkgs at version 2026.6.33. There is no
  `services.openclaw` NixOS module, so the service unit has to be written here.
- `modules/security` currently sets `networking.firewall.enable = false`.

## The job path needs no inbound access

The OpenClaw Discord connector opens an outbound WebSocket to Discord's gateway.
That means no port forwarding, no public IP, and no dynamic DNS are required for
jobs to arrive. A remote device only has to message the bot. Telegram and Slack
behave the same way.

Remote reachability is therefore only needed for two things: waking the machine,
and administrative access to the `openclaw` CLI and the control UI, which binds
to `127.0.0.1:18789`.

## Decision: the machine stays always on

Tailscale cannot send Wake-on-LAN magic packets, because WoL is a layer 2
mechanism and Tailscale operates at layer 3. Every WoL option therefore needs a
device that is already on the LAN to originate the packet. There is no
always-on device on this LAN besides the router, and the ethernet port has no
cable, so all of the wake options carried real setup cost or real reliability
risk:

- Ethernet plus a WoL sender (Pi, NAS, or OpenWrt router) is the most robust
  wake path, but needs hardware that does not exist here.
- WoWLAN over WiFi needs no hardware, and the card does support magic packets,
  but iwlwifi WoWLAN across S3 has a poor reliability record and the association
  must survive suspend.
- Router-native WoL depends on router capabilities that are not confirmed.

The decision is to keep jimbo always on. Idle draw for this hardware is roughly
70 to 100 W, which is the price paid for removing the wake problem entirely.
Suspend plus WoL can be revisited later as an isolated change.

There is a second reason to prefer always-on: a Discord DM sent while the
gateway is offline may never be delivered, because Discord pushes live gateway
events rather than backfilling missed ones. Any sleep-based design has to prove
that behaviour first, otherwise the wake trigger and the job trigger become two
separate actions.

## Models

`modules/llm` already runs llama.cpp with Vulkan support, serving Qwen3.5-9B
Q4_K_M at a 64K context on loopback port 8080. The quantised weights are about
5.5 GB, which fits comfortably in 16 GiB of VRAM, so the 15 GiB of system RAM is
not the binding constraint while the model stays resident on the GPU.

OpenClaw consumes this as an OpenAI-compatible provider at
`http://127.0.0.1:8080/v1`, which `modules/llm` already exposes as the read-only
`llm.baseUrl` option.

The known risk is tool calling: the upstream docs are explicit that small local
models call tools unreliably. The mitigation ladder is to enable Tool Search
first, and to set `compat.supportsTools: false` only as a last resort. The
practical split is to route simple jobs to the local model and keep a cloud
model for anything involving browser automation or multi-step tool use.

Upstream also notes that local models carry none of a hosted provider's safety
filtering. Since this gateway is driven from Discord, tool permissions matter
more here than they do on an interactive laptop.

## Browser automation

OpenClaw drives Chromium over CDP, and uses Playwright for the higher-level
actions such as click, type, snapshot, and PDF. It requires the full Playwright
package rather than the core-only variant, and it only detects Playwright at
gateway startup, so the service must be restarted after Playwright is installed.

Run headless. Headed mode needs a live Hyprland session, which a headless
always-on host will not reliably have. On NixOS the bundled Chromium needs
either `playwright-driver.browsers` supplied through Nix or an FHS wrapper; this
is the least certain part of the plan.

## Service and administrative access

- Install `pkgs.openclaw` and run it as a systemd user service. Set
  `users.users.aaron.linger = true` so it runs when nobody is logged in. The
  existing `llama-server` user service in `modules/llm` needs the same lingering
  to survive logout.
- Keep `gateway.bind = "loopback"`. Reach the control UI either through an SSH
  tunnel (`ssh -N -L 18789:127.0.0.1:18789`) or by setting
  `gateway.tailscale.mode = "serve"`, which configures Tailscale Serve while
  leaving the gateway itself on loopback. Do not use Tailscale Funnel, which
  publishes the dashboard to the public internet.
- `DISCORD_BOT_TOKEN` must be present in `~/.openclaw/.env` for a service
  install to resolve it after a restart. It must not be written through Nix,
  because the resulting file would be world-readable in the Nix store.
- Re-enable the firewall once the machine is remotely reachable.

## Planned changes

1. `modules/llm`: add lingering for the primary user, and disable suspend so the
   host stays reachable (`services.logind` idle action off, and disable the
   `sleep` target).
2. New `modules/openclaw`: `pkgs.openclaw`, a systemd user service, and
   generated configuration with `gateway.bind = "loopback"`,
   `gateway.tailscale.mode = "serve"`, and a provider pointed at
   `config.llm.baseUrl`. The bot token is read from `~/.openclaw/.env`, which is
   created once by hand.
3. New `modules/tailscale`: `services.tailscale.enable`. `tailscale up` is
   interactive and is run once by hand.
4. `modules/security`: enable the firewall, allowing only SSH and the
   `tailscale0` interface. This changes the security posture of a machine in
   daily use, so it belongs in its own commit.
5. Supply Playwright's browsers through Nix for headless Chromium, and confirm
   the gateway detects them after a restart.

Two things cannot be verified without building: Playwright's bundled-Chromium
path on NixOS, and whether Qwen3.5-9B calls OpenClaw's tools reliably enough to
be useful. Both need testing rather than assumption.

## References

- <https://docs.openclaw.ai/channels/discord>
- <https://docs.openclaw.ai/gateway/local-models>
- <https://docs.openclaw.ai/gateway/remote>
- <https://docs.openclaw.ai/gateway/tailscale>
- <https://docs.openclaw.ai/tools/browser>
- <https://tailscale.com/blog/wake-on-lan-tailscale-upsnap>
- <https://github.com/tailscale/tailscale/issues/306>

## Build results

Steps 1 to 3 of the planned changes are implemented and switched on jimbo. What
the build proved, and what it corrected in the plan above:

- `pkgs.openclaw` is marked insecure in nixpkgs, because it parses untrusted
  content with an LLM that has full access to the system. It therefore needs
  `nixpkgs.config.permittedInsecurePackages = [ "openclaw-2026.6.33" ]`, which
  pins the version string and has to be bumped on every OpenClaw update.
- OpenClaw is not in cache.nixos.org or either of the configured Cachix caches,
  so it builds locally. The `tsdown` bundler step needs about 9 GiB resident,
  which the OOM killer terminated on a 15 GiB machine with no swap. A 16 GiB
  swapfile was added to the jimbo host config, and the build then succeeded.
  Hibernation is disabled, so the swapfile does not need to fit RAM.
- Setting `OPENCLAW_NIX_MODE=1` makes OpenClaw treat `openclaw.json` as
  immutable and disables self-mutation. That removes the concern about the
  config being a Nix store path: the rule against symlinked config only applies
  to OpenClaw-owned writes, which Nix mode turns off. `OPENCLAW_CONFIG_PATH`
  points straight at the generated store file, and `OPENCLAW_STATE_DIR` keeps
  mutable state in `~/.openclaw`.
- The gateway refuses to start unless `gateway.mode` is set, so the generated
  config sets `gateway.mode = "local"`.
- Without a gateway auth token, the gateway generates a fresh one on every
  restart and CLI clients cannot connect. The token is read from
  `OPENCLAW_GATEWAY_TOKEN` in `~/.openclaw/.env`, alongside
  `DISCORD_BOT_TOKEN`, so neither secret reaches the Nix store.
- An agent turn against the local model succeeded end to end: the gateway
  cataloged 33 tools behind Tool Search and Qwen3.5-9B answered through
  `http://127.0.0.1:8080/v1/chat/completions`. Tool-calling quality under real
  jobs is still untested.
- Suspend is blocked rather than merely unused: `IdleAction=ignore` plus masked
  `sleep`, `suspend`, `hibernate` and `hybrid-sleep` targets. `systemctl
  suspend` now fails with "Access denied".

Remaining manual steps, which cannot be done from Nix:

1. Write `~/.openclaw/.env` with `DISCORD_BOT_TOKEN` and
   `OPENCLAW_GATEWAY_TOKEN`, mode 600. Until it exists, the gateway service
   restarts every 10 seconds and logs a missing-secret error.
2. Run `tailscale up`. `tailscaled` runs but is logged out.

Steps 4 and 5 of the plan, the firewall and Playwright's browsers, are not
done.
