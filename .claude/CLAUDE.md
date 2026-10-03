# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Nix flake configuring three machines for a single user (`aaron`):

- `jimbo`, NixOS PC, `x86_64-linux`
- `piggys-MBP`, MacBook via nix-darwin, `aarch64-darwin`
- `spike`, always-on NixOS box, `x86_64-linux`

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

Update this file in the same branch as any change that makes it wrong.
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

- SSH: `ssh aaron@spike.local` (key auth, resolved over mDNS).
- The repo is cloned at `~/workspace/jimbo` on `main`.
  To deploy, push to `main`, then on spike: `git pull && just`.
- SSH accepts keys only, declared in `modules/hosts/spike`.
  `sudo` is passwordless (`wheelNeedsPassword = false`), so run the deploy over SSH directly.
- Headless. Docker is managed directly with `docker`/`docker compose`; `aaron` is in the `docker` group.
- Grafana on `:3001`, backed by Prometheus scraping node_exporter and cAdvisor.
- Bowerbird (`modules/hosts/spike/bowerbird.nix`) runs the job application pipeline from a clone of `kranners/bowerbird` at `/srv/bowerbird`, made by hand as `aaron` with `npm ci` run in it.
  Its secrets and settings live in `/srv/bowerbird/.env`, owner `bowerbird`, mode 600, written by hand.
  `bowerbird-compose.service` runs `compose.production.yml` as root: Postgres on `127.0.0.1:5432` and the portal on `:3000`.
  `bowerbird-display.service` runs Xvfb `:99` with openbox, `bowerbird-remote-view.service` serves it through x11vnc and noVNC on `:6080`, and `bowerbird-worker.service` runs `jobs/src/worker.ts` on it, all as the system user `bowerbird` with state in `/var/lib/bowerbird`.
  The worker starts once the display is up and Postgres accepts connections, and every unit that needs the checkout is skipped while it is missing.
  `bowerbird-backup.timer` dumps the database nightly into `/var/lib/bowerbird-backups`, keeping 14 days.
  Ports `3000` and `6080` are open only on `wlp2s0` and `wg0`.
  To deploy: `ssh aaron@spike.local 'cd /srv/bowerbird && git pull && npm ci && sudo systemctl restart bowerbird-compose bowerbird-worker'`.
- Hardware watchdog (`wdat_wdt`) is armed by systemd, and the kernel reboots 10 s after a panic.
- WireGuard `wg0` on UDP `51820` at `spike.cute.engineer` (kept current by cloudflare-dyndns, token in `/var/lib/secrets/cloudflare-dyndns-token`), spike is `10.100.0.1`.
  Its private key is generated on first boot at `/var/lib/wireguard/private`.
- Claude Code Remote Control (`claude-remote-control.service`) serves sessions from `~/workspace` to claude.ai/code as `spike`.
- Discord threads (`discord-threads.service`) runs `kranners/claude-discord-threads` as `aaron` from `~/workspace/claude-discord-threads`, giving each Discord thread its own Claude Code session through the Nix-managed `claude`.
  That repository is private, so the checkout pulls over SSH with a read-only deploy key, `~/.ssh/claude-discord-threads-deploy`, set as its `core.sshCommand` because home-manager owns `~/.ssh/config`.
  Its bot token lives in `~/.claude/channels/discord/.env` as `DISCORD_BOT_TOKEN`, mode 600, written by hand.
  Its allowlist is `~/.claude/channels/discord/access.json`, re-read on every message: `{"dmPolicy":"allowlist","allowFrom":["193903125994799114"],"groups":{"<channel id>":{"requireMention":false,"allowFrom":[]}}}`.
  `/project <path>` in an opted-in channel binds it to a repo, and each new thread there gets a worktree under `<repo>/.claude/worktrees/`.
  `/done` removes a thread's worktree unless something in it is uncommitted, keeps its branch, and posting in the thread again restores it.
  To deploy a new version, `git pull` in the checkout and `sudo systemctl restart discord-threads`; the restart runs `bun install --frozen-lockfile` first.

### Neovim

`modules/neovim/lua`, `after/`, and `lazy-lock.json` are symlinked into `~/.config/nvim` with `mkOutOfStoreSymlink`, resolved through the `repoPath` option (relative to the home directory, default `workspace/jimbo`).

Lua edits take effect immediately without a rebuild; only `init.lua` and the LSP/tool packages in `default.nix` require a rebuild.

Lua is formatted with stylua (`stylua.toml` at repo root).

### Other directories

- `voyager/`, QMK keymap for a ZSA Voyager keyboard; built/flashed externally with `qmk`, not part of the flake.
- `assets/`, static assets.

