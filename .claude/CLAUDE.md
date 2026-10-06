# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Nix flake configuring four machines for a single user (`aaron`):

- `jimbo`, NixOS PC, `x86_64-linux`
- `piggys-MBP`, MacBook via nix-darwin, `aarch64-darwin`
- `spike`, always-on NixOS box, `x86_64-linux`
- `framer`, NixOS Surface Book 2 laptop, `x86_64-linux`

## Commands

```sh
just          # rebuild + switch the current host (runs `git add .` first, then nh)
just check    # nix flake check --show-trace (this is what CI runs)
```

`just` stages everything before building because flakes only see git-tracked files.

## Workflow

The landing check is `just check`.
The weekly `flake-update-*` branches are the exception: they land through the pull request the bot opens.
CI runs `just check`'s `nix flake check` on every push to every branch.
`.claude/worktrees/` is gitignored so the `git add .` in `just` never stages a worktree.

Update this file, or `modules/hosts/spike/CLAUDE.md`, in the same branch as any change that makes it wrong.
It keeps one sentence per line, so git merges edits from two branches sentence by sentence.

## Architecture

Instead of writing `nixosConfigurations`/`darwinConfigurations` directly, `flake.nix` runs `lib.evalModules` over `./modules` once per host and merges the results with `lib.recursiveUpdate`.

Every directory under `modules/` is a config module that contributes to one or more of these options (defined in `modules/default.nix`):

- `sharedSystemModule` / `sharedHomeModule` — both platforms
- `nixosSystemModule` / `nixosHomeModule` — Linux only
- `darwinSystemModule` / `darwinHomeModule` — macOS only

`modules/default.nix` assembles these into the real `nixosConfigurations`/`darwinConfigurations` (guarded by platform, parsed from `host.system`).
`modules/home/default.nix` wires the home modules into home-manager for `host.username`.

`modules/default.nix` imports its first list of modules on every host, and its second list only when `host.desktop` is true.

**To add configuration:** create `modules/<name>/default.nix` returning an attrset with the relevant option keys above, and add `./<name>` to the `imports` list in `modules/default.nix`, in the `host.desktop` list if it only makes sense on a machine with a screen.

Modules receive `inputs` (flake inputs) and `host` (`{ system, hostname, username, desktop }`) via `specialArgs`, in addition to the usual `pkgs`/`lib`/`config`.
Because `host` is a `specialArg`, `imports` may depend on it, whereas depending on `config` there recurses infinitely.

### Hosts

`modules/hosts/<host>/` holds facts about one machine only: hardware, bootloader, hostname, state versions.
Only the directory named exactly `host.hostname` is imported, so it applies to that machine alone.

### spike

`spike` is headless (`desktop = false`), so it gets the shared modules and home-manager but none of the desktop ones.
Its files under `modules/hosts/spike` are plain NixOS modules, imported through `nixosSystemModule`.
`modules/hosts/spike/CLAUDE.md` is appended to the personal `CLAUDE.md` on spike alone, so every Claude Code session there knows it is on production and how the host is run.

- SSH: `ssh aaron@spike.local` (key auth, resolved over mDNS).
- The repo is cloned at `~/workspace/jimbo` on `main`.
  To deploy, push to `main`, then on spike: `git pull && just`.
- SSH accepts keys only, declared in `modules/hosts/spike`.
  `sudo` is passwordless (`wheelNeedsPassword = false`), so run the deploy over SSH directly.
- Headless. Docker is managed directly with `docker`/`docker compose`; `aaron` is in the `docker` group.
- Grafana listens on `127.0.0.1:3001`, backed by Prometheus scraping node_exporter and cAdvisor.
  Caddy serves it at `https://grafana.spike.cute.engineer`, whose DNS-only A record points at `10.100.0.1`, so it is reached over WireGuard alone.
  Its dashboards, Hardware, Services, Containers and Claude, are provisioned from `modules/hosts/spike/dashboards.nix`, so a switch replaces any edited or added in the UI.
  Prometheus takes Claude Code metrics over OTLP on `localhost`, from `aaron`'s sessions through `~/.claude/settings.json` on spike alone and from `workaholic`'s through its unit, each labelled `job` by `OTEL_SERVICE_NAME`.
- Caddy (`modules/hosts/spike/caddy.nix`) serves HTTPS on `443`, open only on `wg0`.
  Its certificates come from Let's Encrypt by DNS-01, through the `caddy-dns/cloudflare` plugin built in with `pkgs.caddy.withPlugins`.
  It reads the cloudflare-dyndns token as the systemd credential `cloudflare-token`, through Caddy's `{file.*}` placeholder, so the token never reaches the Nix store.
  Spike's network answers every DNS query itself, whatever server it is sent to, and hides answers with private addresses, so Caddy skips its own propagation check, `propagation_timeout -1`, and waits 30 seconds for Let's Encrypt instead.
  The same filter hides `app.bowerbird.cute.engineer` from anything resolving through the home network.
- Bowerbird (`modules/hosts/spike/bowerbird.nix`) runs the job application pipeline from a clone of `kranners/bowerbird` at `/srv/bowerbird`, made by hand as `aaron` with `npm ci` run in it.
  Its secrets and settings live in `/srv/bowerbird/.env`, owner `bowerbird`, mode 600, written by hand.
  `bowerbird-compose.service` runs `compose.production.yml` as root: Postgres on `127.0.0.1:5432` and the portal on `:3000`.
  `bowerbird-display.service` runs Xvfb `:99` with openbox, `bowerbird-remote-view.service` serves it through x11vnc and noVNC on `:6080`, and `bowerbird-worker.service` runs `jobs/src/worker.ts` on it, all as the system user `bowerbird` with state in `/var/lib/bowerbird`.
  The worker starts once the display is up and Postgres accepts connections, and every unit that needs the checkout is skipped while it is missing.
  A stop signals the worker alone, `KillMode=mixed`, which finishes the runs it has going before it exits, and systemd waits 35 minutes, `TimeoutStopSec`, before `SIGKILL`, five more than the worker's own cap on that wait.
  `bowerbird-backup.timer` dumps the database nightly into `/var/lib/bowerbird-backups`, keeping 14 days.
  Caddy serves the portal at `https://app.bowerbird.cute.engineer` and noVNC under its `/vnc/`, where `REMOTE_VIEW_URL` points, and noVNC finds `/vnc/websockify` relative to its page.
  The name's DNS-only A record points at `10.100.0.1`, so the portal is reached over WireGuard alone, and ports `3000` and `6080` are closed to everything but localhost.
  `nodejs_24`, the Node the worker unit runs, is also on the system path so `npm ci` works for `aaron`.
  To deploy by hand: `ssh aaron@spike.local /srv/bowerbird/bin/deploy`, the repository's script, which pulls `main`, runs `npm ci` and restarts only the units whose code changed.
  GitHub Actions runs the same script on every push to Bowerbird's `main`: it joins `wg0` as the peer `github-actions` and logs in as `aaron@10.100.0.1` with a key whose forced command is `/srv/bowerbird/bin/deploy`.
  The script refuses to deploy while a branch other than `main` is checked out in `/srv/bowerbird`, so checking one out there pauses deploys while it is tested.
- Hardware watchdog (`wdat_wdt`) is armed by systemd, and the kernel reboots 10 s after a panic.
- WireGuard `wg0` on UDP `51820` at `spike.cute.engineer` (kept current by cloudflare-dyndns, token in `/var/lib/secrets/cloudflare-dyndns-token`), spike is `10.100.0.1`.
  Its private key is generated on first boot at `/var/lib/wireguard/private`.
  Its peers are `piggys-MBP` at `10.100.0.2`, `phone` at `10.100.0.4`, and `github-actions` at `10.100.0.3`, whose private key lives only in Bowerbird's GitHub secrets.
- Claude Code Remote Control (`claude-remote-control.service`) serves sessions from `~/workspace` to claude.ai/code as `spike`.
- Discord threads (`discord-threads.service`) runs `kranners/claude-discord-threads` as `aaron` from `~/workspace/claude-discord-threads`, giving each Discord thread its own Claude Code session through the Nix-managed `claude`.
  That repository is private, so the checkout pulls over SSH with a read-only deploy key, `~/.ssh/claude-discord-threads-deploy`, set as its `core.sshCommand` because home-manager owns `~/.ssh/config`.
  Pushes go over HTTPS with the `gh` login instead, through the checkout's `remote.origin.pushurl`, so the deploy key never needs write access.
  Its bot token lives in `~/.claude/channels/discord/.env` as `DISCORD_BOT_TOKEN`, mode 600, written by hand.
  Its allowlist is `~/.claude/channels/discord/access.json`, re-read on every message: `{"dmPolicy":"allowlist","allowFrom":["193903125994799114"],"groups":{"<channel id>":{"requireMention":false,"allowFrom":[]}}}`.
  `/project <path>` in an opted-in channel binds it to a repo, and each new thread there gets a worktree under `<repo>/.claude/worktrees/`.
  `/done` removes a thread's worktree unless something in it is uncommitted, keeps its branch, and posting in the thread again restores it.
  `discord-threads-pull.timer` deploys every push to its `main` within 2 minutes: as `aaron` it runs `git pull --ff-only` in the checkout and, when `HEAD` moved, restarts `discord-threads`, which runs `npm ci --omit=dev` first and ends every live thread session, whose unfinished turns replay from the ledger on boot.
  It skips the pull while the checkout is on a branch other than `main`, so checking one out there pauses deploys.
- workaholic (`modules/hosts/spike/workaholic.nix`) runs `kranners/workaholic` from `/srv/workaholic`, cloned by hand as `aaron`, as the system user `workaholic` with no `sudo` and its home in `/var/lib/workaholic`.
  Eight runners, one per thread, `workaholic@1` to `workaholic@8`, are instances of the oneshot `workaholic@.service`, each started by its own timer 3 plus twice its number minutes after boot and 5 minutes after its last run ends, at `Nice=10` and low CPU and IO weights so production stays ahead of it.
  How many issues are worked at once is left to each run's gate on load, memory and Max usage, with eight as the ceiling.
  The runners share `system-workaholic.slice`, capped at `MemoryHigh=7G` and `MemoryMax=8G`, because one run peaks at up to about 4 GiB and spike has no swap, so runs that overrun it are OOM-killed inside the slice rather than production.
  Each run is `src/run.ts` under the `mixed` profile, which runs the gate, then claims one issue no other runner holds and works it with `claude -p`, with `git`, `claude-code`, `nodejs_24` and `curl` on its path, so sessions can run npm landing checks and probe their previews, and `SHELL` set to bash, because the user's own shell is `nologin`.
  Its Claude token from `claude setup-token`, its GitHub token and the token of its own Discord bot, apart from the one `discord-threads` runs as, live in `/var/lib/workaholic/.config/workaholic/` as `claude-token`, `github-token` and `discord-token`, owner `workaholic`, mode 600, written by hand.
  The user lingers, so its runs can leave each issue's preview running as a transient user unit on `4000` plus the issue number, with ports 4000 to 4999 open on `wlp2s0` and `wg0` alone, and `~/.config` is its own, apart from the root-owned token directory, because Chrome cannot start without writing there.
  `TEST_CHROMIUM_PATH` names nixpkgs' Google Chrome, because Playwright's downloaded Chromium cannot run on NixOS, so sessions can run browser tests and record their changes.
  Each run first starts the oneshot `workaholic-pull`, which runs `git pull --ff-only` in `/srv/workaholic` as `aaron`, so every run works from the newest `main` with no restart, and a failed pull leaves the run on the code already there.
  When the pull moves `HEAD`, it also restarts `workaholic-listen`, which keeps `src/listen.ts` connected to Discord as that bot, restarting it 10 s after it exits, to answer its slash commands in issue threads.
  `workaholic-listen` has the runners' path and environment, because `/pickup` starts a run as a transient user unit that takes `PATH`, `SHELL` and `TEST_CHROMIUM_PATH` from it.

### framer

`framer` is a Microsoft Surface Book 2 laptop running NixOS, a desktop host (`desktop = true`), so it gets the same shared and desktop modules as `jimbo`.
Its files under `modules/hosts/framer` are plain NixOS modules, imported through `nixosSystemModule`, the same shape as spike's.

- SSH: `ssh aaron@framer.local` (key auth, resolved over mDNS), keys only, declared in `modules/hosts/framer`.
- Hardware: Intel i5-7300U, one 119 GB NVMe disk with a 1 GB ESP, wifi (`wlp1s0`) and no wired network, two batteries and an `intel_backlight` panel.
  `boot.loader.systemd-boot.configurationLimit` is 5, because that ESP only has room for a few generations.
  `thermald` and `upower` run for the laptop's thermals and battery, and Bluetooth is on at boot.
- Hardware watchdog (`iTCO_wdt`) is armed by systemd, and the kernel reboots 10 s after a panic, the same as spike's.
- It keeps the default sleep and suspend targets, unlike spike, which disables them.
- The `brightness` command from `modules/brightness` drives framer's built-in panel, `intel_backlight`, with brightnessctl, which it picks over DDC/CI because `/sys/class/backlight` has a device here.

### Neovim

`modules/neovim/lua`, `after/`, and `lazy-lock.json` are symlinked into `~/.config/nvim` with `mkOutOfStoreSymlink`, resolved through the `repoPath` option (relative to the home directory, default `workspace/jimbo`).

Lua edits take effect immediately without a rebuild; only `init.lua` and the LSP/tool packages in `default.nix` require a rebuild.

Lua is formatted with stylua (`stylua.toml` at repo root).

### Other directories

- `voyager/`, QMK keymap for a ZSA Voyager keyboard; built/flashed externally with `qmk`, not part of the flake.
- `assets/`, static assets.

