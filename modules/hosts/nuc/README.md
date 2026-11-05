# nuc

The spare Intel NUC, as spike's worker box: first backlogic's runner, then Nix builds for spike, an off-box watchdog for spike and nightly backups, and later perhaps Kokoro's speech.
It is a host of this flake like every other machine, installed remotely with nixos-anywhere and disko, never by hand, so the whole install comes from this repository.
Every role is off until it is switched on below, so nothing changes on spike until then.

## What I need to know about the NUC

- Model, from the sticker underneath or the BIOS's main page.
- Memory in GiB, which sets `nuc.memoryGiB`, and so the swap size and the backlogic runner's memory caps.
- CPU threads, which sets `nuc.cores`.
- Disk type and size, NVMe (`/dev/nvme0n1`) or SATA (`/dev/sda`), from `lsblk` on the installer, which sets `nuc.disk`.
- Wired ethernet or wifi only; it should be on ethernet.
- Whether its network card is Intel, which every NUC's wired one is, so wake on LAN works.
- BIOS settings: UEFI boot on, legacy or CSM boot off, Secure Boot off, power on after AC loss set to on (Power, After Power Failure), and wake on LAN on.

## Installing

1. Make the USB stick: either the stock NixOS minimal ISO from nixos.org, written with `sudo dd if=nixos-minimal.iso of=/dev/<stick> bs=4M status=progress`, or this flake's own `nix build .#nuc-installer-iso` on spike, which is the same installer with sshd on and Aaron's keys on root, so no password is needed.
   With the stock ISO, set a root password on the NUC's own screen with `passwd` once it boots, so nixos-anywhere can log in.
2. Plug the NUC into ethernet and boot it from the stick, pressing F10 at power on for the boot menu.
3. Note its IP, from `ip -4 addr` on its screen or the router, and its disk's name from `lsblk`.
4. Set `nuc.disk`, `nuc.memoryGiB` and `nuc.cores` in `default.nix` if they differ from `/dev/nvme0n1`, 16 and 4, and commit; then, from the jimbo checkout on spike or piggys-MBP, run `just nuc-install <ip> <disk>`.
   It shows the disks, asks for the disk's name before wiping it, installs with nixos-anywhere, and writes the NUC's hardware report to `facter.json` here, which is then committed.
5. On first boot the NUC generates its WireGuard key in `/var/lib/secrets/wireguard-private`, unless one was written there first; `sudo wg show wg0 public-key` on it prints the public half, which goes in `nucPublicKey` in `modules/hosts/spike/wireguard.nix`.
   That makes the NUC spike's peer at `10.100.0.14`, new access, so it waits for Aaron's plain yes; spike forwards nothing from it, so it reaches spike alone, and spike's Prometheus then scrapes its node_exporter.
6. Switch the roles on in `default.nix`'s `nixosSystemModule`, one at a time, in this order.

## The roles

- `nuc.backlogicRunner.enable` runs `backlogic-runner-aaron`, the same unit spike runs, from `modules/backlogic-runner`, claiming tickets from spike's instance on `10.100.0.1:4200`, with `MemoryMax` all but 3 GiB of `nuc.memoryGiB`, `MemoryHigh` a GiB under that, every thread but one and 128 tasks a thread.
  The runner's own memory gate launches a session only while 40% of its `memory.max` is free, so that cap is its concurrency ceiling.
  Turn spike's own off in the same change, `backlogicRunner.enable = false` in `modules/hosts/spike/backlogic.nix`, so only one runner claims tickets.
  By hand on the NUC, as on spike: the runner's clone in `/var/lib/backlogic-runner/workspace/backlogic--service`, its Claude logins in `~/.claude` and `~/.claude-work`, its `~/runner.token`, its GitHub tokens in `~/.config/github-tokens`, `mise install` in its checkouts, and `runner.json` and `cloud-routine.token` copied into `/var/lib/backlogic-runner-config` from spike, since the instance writes those on spike alone.
  Its sessions cannot reach `ssh bowerbird-deploy`, which is spike's localhost alone.
- `nuc.builder.enable` serves Nix builds as `nix-builder`, whose key may only run `nix-daemon --stdio`, from `10.100.0.1` alone.
  On spike, root makes `/var/lib/secrets/nuc-builder-key` by hand, its public half goes in `nuc.builder.clientKeys`, and `nucBuilder` in `modules/hosts/spike/remote-builder.nix` is switched on with the NUC's host key, so spike, and so `jimbo-switch`, builds there.
- `nuc.watchdog.enable` checks every minute that spike answers ping or its Grafana health check over WireGuard, and once it has not for 10 minutes says so once, and again when it is back.
  Butler and `butler-notify` live on spike, so they cannot carry that notice: it goes to the NUC's journal at `crit`, and to a Discord webhook only once Aaron writes its URL into `/var/lib/secrets/spike-watchdog-webhook`, mode 600, such as a webhook for a channel of butler's guild, a credential of its own that waits for his say-so.
  `nuc.watchdog.heartbeatUrl` also checks `butler-monitor`'s last run, from spike's node_exporter on `10.100.0.1:9100`, which spike's firewall closes on `wg0` today, so it stays null until that port is opened to the NUC.
- `nuc.backups.enable` pulls Butler's memory, its asset store, the index and Home Assistant's config from spike at 03:40 each night into dated snapshots in `/var/lib/nuc-backups`, hard-linking what has not changed, and deletes those over 14 days old.
  It logs in as `nuc-backup@10.100.0.1` with `/var/lib/secrets/nuc-backup-key`, made by hand on the NUC, which spike does not authorize yet: that login needs read access to butler's and Home Assistant's state, new access, so it waits for Aaron's plain yes.
