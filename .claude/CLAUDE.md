# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Nix flake configuring two machines for a single user (`aaron`):

- `jimbo`, NixOS PC, `x86_64-linux`
- `piggys-MBP`, MacBook via nix-darwin, `aarch64-darwin`

## Commands

```sh
just          # rebuild + switch for the current platform (runs `git add .` first, then nh)
just check    # nix flake check --show-trace (this is what CI runs)
```

`just` stages everything before building because flakes only see git-tracked files.

## Architecture

Instead of writing `nixosConfigurations`/`darwinConfigurations` directly, `flake.nix` runs `lib.evalModules` over `./modules` once per host and merges the results with `lib.recursiveUpdate`.

Every directory under `modules/` is a config module that contributes to one or more of these options (defined in `modules/default.nix`):

- `sharedSystemModule` / `sharedHomeModule` — both platforms
- `nixosSystemModule` / `nixosHomeModule` — Linux only
- `darwinSystemModule` / `darwinHomeModule` — macOS only

`modules/default.nix` assembles these into the real `nixosConfigurations`/`darwinConfigurations` (guarded by platform, parsed from `host.system`). `modules/home/default.nix` wires the home modules into home-manager for `host.username`.

**To add configuration:** create `modules/<name>/default.nix` returning an attrset with the relevant option keys above, and add `./<name>` to the `imports` list in `modules/default.nix`.

Modules receive `inputs` (flake inputs) and `host` (`{ system, hostname, username }`) via `specialArgs`, in addition to the usual `pkgs`/`lib`/`config`.

### Hosts

`modules/hosts/<host>/` holds facts about one machine only: hardware, bootloader, hostname, state versions.

### Neovim

`modules/neovim/lua`, `after/`, and `lazy-lock.json` are symlinked into `~/.config/nvim` with `mkOutOfStoreSymlink`, resolved through the `repoPath` option (relative to the home directory, default `workspace/jimbo`).

Lua edits take effect immediately without a rebuild; only `init.lua` and the LSP/tool packages in `default.nix` require a rebuild.

Lua is formatted with stylua (`stylua.toml` at repo root).

### Other directories

- `voyager/`, QMK keymap for a ZSA Voyager keyboard; built/flashed externally with `qmk`, not part of the flake.
- `assets/`, static assets.


# `nixos-modules`

You are on the `nixos-modules` branch, to be merged into `main`.

The purpose of this branch is to move all the legacy content out from `nixos/` and into the new `modules/` architecture.

## Scope

In scope:

- Empty `nixos/`, delete the directory, drop both import sites.
- Add `modules/hosts/jimbo/` for machine facts.
- Add `theme.colors` and `repoPath` options.
- Consolidate per app, one module owns cask + package + service + bind.
- Delete the dead and duplicated config listed below.

Out of scope:

- Splitting `apps/`, promoting `home/` contents, renaming `preferences/` or `nixpkgs-config/`.
- Swapping `xdg-desktop-portal-wlr` for the Hyprland portal. Straight move.

## Migration rules

- Top-level module args are the *outer* `evalModules` args, not NixOS or home-manager ones.
- Anything using `config` or `modulesPath` must use function form: `nixosSystemModule = { config, ... }: { ... }`.
- Getting this wrong fails as infinite recursion. Run `just check` after every move.
- Top-level `pkgs` is a second nixpkgs eval. Overlays set in `*SystemModule` do not apply to it.
- Use `host.hostname` / `host.username`, never the literals `jimbo` / `aaron`.
- Hyprland `settings` merges fine across modules. Lists concatenate.

## Order

1. `modules/hosts/jimbo/` + `theme.colors` + `repoPath`.
2. `nixos/system/*`.
3. Simple home modules: swaync, wpaperd, avizo.
4. Per-app: obsidian, discord, plexamp, spotify, browsers.
5. Waybar last. Needs `theme.colors`.
6. Delete `nixos/`.

## Where things go

`modules/hosts/jimbo/`:

- `system/hardware.nix` verbatim. Needs `modulesPath`, so function form.
- `system/boot.nix`, GRUB and os-prober.
- `AMD_VULKAN_ICD` from `system/graphics.nix`.
- `networking.hostName`, use `host.hostname`.
- Move `state-versions/` here.

New topic modules:

- `system/graphics.nix` less the AMD bit, `modules/graphics/`.
- `system/sound.nix`, `modules/sound/`.
- `system/security.nix`, `modules/security/`.
- `system/xdg.nix`, `modules/xdg/`. Takes `xdg.enable` and `xdg.userDirs` from `home/default.nix`.
- `system/locale.nix`, `modules/locale/`. `time.timeZone` goes to `sharedSystemModule`.
- `system/steam.nix`, `modules/gaming/`. Absorbs the game packages from `apps/` and the game window rules from `hyprland/`.
- `networking.networkmanager`, `modules/networking/`.
- `programs.gnupg.agent` + darwin `gnupg` brew + `GPG_TTY` from `git/`, `modules/gnupg/`.
- `home/waybar.nix` + `home/swaync.nix`, `modules/waybar/`. Style reads `theme.colors`.
- `home/wpaperd.nix`, `modules/wallpaper/`.
- `home/avizo.nix`, `modules/avizo/`. Fix the `assets/` relative path.

Per-app modules, each owning cask + package + service + Hyprland bind:

- `modules/obsidian/`, from `home/obsidian-service.nix`, `apps/` cask and pkg, `$mod,O`.
- `modules/discord/`, from `home/vesktop.nix`, `apps/` cask, `$mod,V`, exec-once.
- `modules/plexamp/`, from `home/plexamp.nix`, `apps/` cask and pkg, `$mod,P`.
- `modules/spotify/`, from `apps/` cask and pkg, `$mod,Y`.
- `modules/browser/`, from `apps/` casks and pkg, `$mod,B` and `$mod,C`.

Into existing modules:

- `programs.zsh.enable`, `modules/zsh/` `nixosSystemModule`.
- `services.openssh.enable`, `modules/ssh/`.
- `programs.dconf.enable` and `QT_QPA_PLATFORM`, `modules/theme/`.
- `programs.home-manager.enable`, `modules/home/` `sharedHomeModule`.
- `systemd.user.startServices`, `modules/home/` `nixosHomeModule`.

## Delete, do not move

- `home/default.nix` `home.username` and `home.homeDirectory`. Home-manager sets both from `users.users`. Only works today because both say `aaron`.
- `system/security.nix` `pam.services.swaylock`. Swaylock is not installed.
- `home/plexamp.nix` sway window rule. Sway is not the compositor.
- `pkgs.plexamp` in `apps/`. Duplicate.
- `pkgs.wl-clipboard` in `apps/`. Duplicate of `hyprland/`.
- `pkgs.pipewire` in `apps/`. `sound.nix` enables the service.
- `git/default.nix` `nixosSystemModule.programs.git`. Different name and email to the home config.
- `modules/overlays/`. One fish override, fish is unused.

