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

Each change is made on a short-lived local branch in a worktree of its own, holding one feature or fix.
`claude -w <name>` starts a session in `.claude/worktrees/<name>` on a branch named `worktree-<name>`; the directory is gitignored so the `git add .` in `just` never stages it.

A branch lands by fetching `origin`, rebasing onto `origin/main`, passing `just check`, then running `git push origin HEAD:main`.
A rejected push means `main` moved, so landing starts again from the fetch.
A landed branch is deleted, locally and on `origin`.
The weekly `flake-update-*` branches are the exception: they land through the pull request the bot opens.
CI runs `just check`'s `nix flake check` on every push to every branch, so a red `main` is fixed forward.

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
- Grafana on `:3000`, backed by Prometheus scraping node_exporter and cAdvisor.
- Hardware watchdog (`wdat_wdt`) is armed by systemd, and the kernel reboots 10 s after a panic.
- WireGuard `wg0` on UDP `51820` at `spike.cute.engineer` (kept current by cloudflare-dyndns, token in `/var/lib/secrets/cloudflare-dyndns-token`), spike is `10.100.0.1`.
  Its private key is generated on first boot at `/var/lib/wireguard/private`.
- Claude Code Remote Control (`claude-remote-control.service`) serves sessions from `~/workspace` to claude.ai/code as `spike`.
- OpenClaw gateway (`openclaw.service`) runs as `aaron` on loopback, reached through Discord or `openclaw tui` over SSH.
  Claude is its only model, through the `claude-cli` backend.
  Secrets live in `~/.openclaw/.env`.

### Neovim

`modules/neovim/lua`, `after/`, and `lazy-lock.json` are symlinked into `~/.config/nvim` with `mkOutOfStoreSymlink`, resolved through the `repoPath` option (relative to the home directory, default `workspace/jimbo`).

Lua edits take effect immediately without a rebuild; only `init.lua` and the LSP/tool packages in `default.nix` require a rebuild.

Lua is formatted with stylua (`stylua.toml` at repo root).

### Other directories

- `voyager/`, QMK keymap for a ZSA Voyager keyboard; built/flashed externally with `qmk`, not part of the flake.
- `assets/`, static assets.

