{
  config,
  lib,
  pkgs,
  ...
}:
let
  root = "/var/lib/backlogic-source";

  # The code that runs on spike: the instance's checkout and the runner's, each mirrored by its own owner.
  mirrors = {
    instance = {
      checkout = "/srv/backlogic";
      user = "aaron";
    };
    runner = {
      checkout = "${config.users.users.backlogic-runner.home}/workspace/backlogic--service";
      user = "backlogic-runner";
    };
  };

  # Extracts the checkout's HEAD, tracked files alone, into <dest>/<commit>, drops anything named like a
  # secret or a database, and points <dest>/current at it, so readers never see a half-written tree.
  backlogic-source-mirror = pkgs.writeShellApplication {
    name = "backlogic-source-mirror";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.findutils
      pkgs.git
      pkgs.gnutar
    ];
    text = ''
      src=$1
      dest=$2
      commit=$(git -C "$src" rev-parse HEAD)
      if [ "$(readlink "$dest/current" 2>/dev/null)" = "$commit" ] && [ -d "$dest/$commit" ]; then
        exit 0
      fi

      next="$dest/.next"
      rm -rf "$next"
      mkdir "$next"
      git -C "$src" archive --format=tar "$commit" | tar --extract --no-same-owner --directory "$next"
      find "$next" \( -name '.env' -o -name '.env.*' -o -name '*.env' -o -name '*.pem' -o -name '*.key' \
        -o -name '*.token' -o -name '*.p12' -o -name 'id_rsa*' -o -name 'id_ed25519*' \
        -o -name '.credentials*' -o -name 'credentials.json' -o -name '*.sqlite*' -o -name '*.db' -o -name '*.db-*' \) \
        -prune -exec rm -rf {} +
      git -C "$src" log -1 --format='%H%n%ci%n%s' "$commit" > "$next/.backlogic-commit"
      chmod -R u+rwX,go+rX,go-w "$next"

      rm -rf "''${dest:?}/$commit"
      mv -T "$next" "$dest/$commit"
      ln -sfn "$commit" "$dest/current.tmp"
      mv -T "$dest/current.tmp" "$dest/current"
      find "$dest" -mindepth 1 -maxdepth 1 -type d -regextype posix-extended -regex '.*/[0-9a-f]{40}' \
        ! -name "$commit" -exec rm -rf {} +
      echo "Mirrored $src at $commit into $dest/current"
    '';
  };
in
{
  systemd.tmpfiles.rules = [
    "d ${root} 0755 root root -"
  ]
  ++ map (name: "d ${root}/${name} 0755 ${mirrors.${name}.user} root -") (builtins.attrNames mirrors);

  systemd.services = {
    # butler reads the mirror with its own Read, Glob and Grep, and butler-shell's scripts read it too,
    # while /srv and the runner's home stay hidden from both.
    butler.serviceConfig.BindReadOnlyPaths = [ "-${root}" ];
    "butler-shell@".serviceConfig.BindReadOnlyPaths = [ "-${root}" ];
  }
  // lib.mapAttrs' (
    name: mirror:
    lib.nameValuePair "backlogic-source-${name}" {
      description = "Mirror the tracked source of backlogic's ${name} checkout, read-only, for butler";
      unitConfig.ConditionPathExists = "${mirror.checkout}/.git";
      serviceConfig = {
        Type = "oneshot";
        User = mirror.user;
        UMask = "0022";
        Nice = 19;
        IOSchedulingClass = "idle";
        ExecStart = "${lib.getExe backlogic-source-mirror} ${mirror.checkout} ${root}/${name}";
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ReadWritePaths = [ "${root}/${name}" ];
      };
    }
  ) mirrors;

  # Each run copies only when the checkout's HEAD moved, so a five-minute poll costs one rev-parse.
  systemd.timers = lib.mapAttrs' (
    name: _:
    lib.nameValuePair "backlogic-source-${name}" {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "3min";
        OnUnitInactiveSec = "5min";
      };
    }
  ) mirrors;
}
