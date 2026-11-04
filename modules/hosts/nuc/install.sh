#!/usr/bin/env bash
# Installs the nuc host onto a NUC booted from the NixOS installer, over ssh, wiping its one disk.
# Run from the root of the jimbo checkout on piggys-MBP or spike: just nuc-install <ip> <disk>
set -euo pipefail

ip=${1:?usage: just nuc-install <the NUC installer IP> <disk, such as /dev/nvme0n1 or /dev/sda>}
disk=${2:?usage: just nuc-install <the NUC installer IP> <disk, such as /dev/nvme0n1 or /dev/sda>}
nix=(nix --extra-experimental-features 'nix-command flakes')
report=modules/hosts/nuc/facter.json

flake_disk=$("${nix[@]}" eval --raw .#nixosConfigurations.nuc.config.nuc.disk)
if [ "$disk" != "$flake_disk" ]; then
  echo "The flake installs to $flake_disk, not $disk: set nuc.disk = \"$disk\"; in modules/hosts/nuc/default.nix's nixosSystemModule, commit, and run this again." >&2
  exit 1
fi

echo "The NUC at $ip has these disks; everything on $disk is about to be wiped:"
ssh -o StrictHostKeyChecking=accept-new "root@$ip" lsblk -d -o NAME,SIZE,MODEL,TRAN
read -r -p "Type the disk's name ($disk) to wipe it and install: " answer
[ "$answer" = "$disk" ] || { echo "Not installing." >&2; exit 1; }

# The flake sees only files git knows, so the report nixos-anywhere writes is added before it is written.
[ -e "$report" ] || echo '{}' > "$report"
git add --intent-to-add "$report"

# A Mac cannot build x86_64-linux, so the installer builds the system itself there.
build=()
[ "$(uname -s)-$(uname -m)" = Linux-x86_64 ] || build=(--build-on remote)

"${nix[@]}" run github:nix-community/nixos-anywhere -- \
  --flake .#nuc \
  --target-host "root@$ip" \
  --generate-hardware-config nixos-facter "$report" \
  "${build[@]}"

git add "$report"
echo "Installed. Commit $report, then follow the first-boot steps in modules/hosts/nuc/README.md."
