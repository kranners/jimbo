{ lib, ... }:
let
  # Removes every generation of each Nix profile but the newest `keep`, the current one and, for the system profile, the booted one.
  # Given no profiles, it prunes them all: the system's, every per-user one and every home's, home-manager's among them.
  pruneGenerations =
    pkgs:
    pkgs.writeShellApplication {
      name = "prune-generations";
      runtimeInputs = [
        pkgs.coreutils
        pkgs.gnused
      ];
      text = ''
        keep=''${1:?usage: prune-generations <keep> [profile...]}
        shift
        nix_env=/run/current-system/sw/bin/nix-env
        if [ "$#" -eq 0 ]; then
          shopt -s nullglob
          set -- /nix/var/nix/profiles/system /nix/var/nix/profiles/per-user/*/* /root/.local/state/nix/profiles/* /home/*/.local/state/nix/profiles/* /Users/*/.local/state/nix/profiles/* /var/lib/*/.local/state/nix/profiles/*
        fi
        booted=$(readlink -f /run/booted-system 2>/dev/null || true)
        deleted=0
        for profile in "$@"; do
          # Only a profile's own link, never one of its generation links.
          [ -L "$profile" ] || continue
          case "$profile" in *-[0-9]*-link) continue ;; esac
          if [ "$profile" = /nix/var/nix/profiles/system ] && [ -s /var/lib/jimbo-switch/failed ]; then
            echo "Keeping every system generation: the last switch failed" >&2
            continue
          fi
          current=$(readlink "$profile")
          gens=$(for link in "$profile"-*-link; do
            [ -L "$link" ] || continue
            n=''${link#"$profile"-}
            n=''${n%-link}
            case "$n" in "" | *[!0-9]*) continue ;; esac
            echo "$n"
          done | sort -n)
          old=()
          for n in $(echo "$gens" | head -n -"$keep"); do
            link="$profile-$n-link"
            [ "$(basename "$current")" != "$(basename "$link")" ] || continue
            [ -z "$booted" ] || [ "$(readlink -f "$link")" != "$booted" ] || continue
            old+=("$n")
          done
          [ "''${#old[@]}" -gt 0 ] || continue
          "$nix_env" --profile "$profile" --delete-generations "''${old[@]}"
          deleted=$((deleted + ''${#old[@]}))
        done
        echo "Deleted $deleted generations, keeping the newest $keep of each profile"
      '';
    };

  # One keep-count for every host, read by the garbage collection, spike's switch, its boot menu and its monitor.
  keepOption = {
    options.jimbo.keepGenerations = lib.mkOption {
      description = "How many of the newest generations of each Nix profile to keep; the current and booted ones are always kept too.";
      type = lib.types.ints.positive;
      default = 3;
    };
  };

  nixpkgs.config = {
    allowUnfree = true;
  };

  nix = {
    settings = {
      # Enable Flakes
      experimental-features = [
        "nix-command"
        "flakes"
      ];

      # Allow root users access to the Nix store
      trusted-users = [
        "root"
        "@wheel"
      ];
      fallback = false;

      extra-substituters = [
        "https://nix-community.cachix.org"
        "https://kranners.cachix.org"
      ];

      extra-trusted-public-keys = [
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "kranners.cachix.org-1:ZuxIgFNLP2qrpRXPKGMV1U+GErsAFU4Em4sqoOkJ0no="
      ];
    };

    # nix-collect-garbage can only age generations out, so they are pruned by count before it runs and it only deletes dead store paths.
    gc = {
      automatic = true;
      options = "";
    };
  };
in
{
  nixosSystemModule =
    { config, pkgs, ... }:
    {
      imports = [ keepOption ];
      inherit nixpkgs;
      nix = lib.recursiveUpdate nix { gc.dates = lib.mkDefault "weekly"; };
      environment.systemPackages = [ (pruneGenerations pkgs) ];
      systemd.services.nix-gc.preStart = "${lib.getExe (pruneGenerations pkgs)} ${toString config.jimbo.keepGenerations}";
    };
  darwinSystemModule =
    { config, pkgs, ... }:
    {
      imports = [ keepOption ];
      inherit nix nixpkgs;
      environment.systemPackages = [ (pruneGenerations pkgs) ];
      launchd.daemons.nix-gc.command = lib.mkForce "${pkgs.writeShellScript "nix-gc" ''
        ${lib.getExe (pruneGenerations pkgs)} ${toString config.jimbo.keepGenerations}
        exec ${config.nix.package}/bin/nix-collect-garbage
      ''}";
    };
}
