{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.nuc.backups;

  # Pulls each path from spike over WireGuard into a dated snapshot, hard-linking what has not changed from the
  # last one, so a night costs only what changed, then deletes snapshots older than keepDays.
  nuc-backup = pkgs.writeShellApplication {
    name = "nuc-backup";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.findutils
      pkgs.openssh
      pkgs.rsync
    ];
    text = ''
      root=${cfg.directory}
      today=$(date +%F)
      previous=$(find "$root" -mindepth 1 -maxdepth 1 -type d -name '20*' ! -name "$today" | sort | tail -n 1)
      mkdir -p "$root/$today"
      ssh_command="ssh -i ${cfg.keyFile} -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=${cfg.knownHostsFile}"
      failed=0
      ${lib.concatMapStrings (
        { name, path }:
        ''
          link=()
          [ -z "$previous" ] || [ ! -d "$previous/${name}" ] || link=(--link-dest "$previous/${name}")
          if ! rsync -a --delete --numeric-ids "''${link[@]}" -e "$ssh_command" \
            ${lib.escapeShellArg "${cfg.source}:${path}/"} "$root/$today/${name}/"; then
            echo "nuc-backup: copying ${name} from ${path} failed" >&2
            failed=1
          fi
        ''
      ) cfg.paths}
      find "$root" -mindepth 1 -maxdepth 1 -type d -name '20*' -mtime +${toString cfg.keepDays} -exec rm -rf {} +
      exit "$failed"
    '';
  };
in
{
  options.nuc.backups = {
    enable = lib.mkEnableOption "nightly pulls of Butler's memory, its asset store, the index and Home Assistant's config from spike";

    source = lib.mkOption {
      description = "The ssh login on spike the backups read through, which spike must authorize, read-only, before this works.";
      type = lib.types.str;
      default = "nuc-backup@10.100.0.1";
    };

    keyFile = lib.mkOption {
      description = "The NUC's backup key, made by hand with ssh-keygen, mode 600.";
      type = lib.types.str;
      default = "/var/lib/secrets/nuc-backup-key";
    };

    knownHostsFile = lib.mkOption {
      description = "spike's host key for the backup login.";
      type = lib.types.str;
      default = "/var/lib/secrets/nuc-backup-known-hosts";
    };

    directory = lib.mkOption {
      description = "Where the dated snapshots live.";
      type = lib.types.str;
      default = "/var/lib/nuc-backups";
    };

    keepDays = lib.mkOption {
      description = "How many days of snapshots to keep.";
      type = lib.types.ints.positive;
      default = 14;
    };

    paths = lib.mkOption {
      description = "What to copy from spike, each into its own folder of a snapshot.";
      type = lib.types.listOf (
        lib.types.submodule {
          options.name = lib.mkOption { type = lib.types.str; };
          options.path = lib.mkOption { type = lib.types.str; };
        }
      );
      default = [
        {
          name = "butler-memory";
          path = "/var/lib/butler/memory";
        }
        {
          name = "butler-index";
          path = "/var/lib/butler-index";
        }
        {
          name = "butler-assets";
          path = "/var/lib/butler/assets";
        }
        {
          name = "home-assistant";
          path = "/var/lib/hass";
        }
      ];
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.tmpfiles.rules = [ "d ${cfg.directory} 0700 root root -" ];

    systemd.services.nuc-backup = {
      description = "Pull Butler's memory, its asset store, the index and Home Assistant's config from spike";
      after = [ "wireguard-wg0.service" ];
      unitConfig.ConditionPathExists = cfg.keyFile;
      serviceConfig = {
        Type = "oneshot";
        Nice = 19;
        IOSchedulingClass = "idle";
        ExecStart = lib.getExe nuc-backup;
      };
    };

    systemd.timers.nuc-backup = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*-*-* 03:40";
        Persistent = true;
        RandomizedDelaySec = "10min";
      };
    };
  };
}
