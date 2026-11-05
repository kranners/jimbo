{
  config,
  lib,
  pkgs,
  ...
}:
let
  state = "/var/lib/butler-work";

  substitutions = {
    "@selfFix@" = "${config.users.users.butler.home}/self-fix";
    "@kanban@" = lib.getExe config.butler.commands.kanban.package;
    "@git@" = lib.getExe pkgs.git;
    "@limits@" = "/var/lib/claude-limits";
  };

  # builders.py without its main, so the snapshot reads the change records exactly as the digest does.
  builders =
    builtins.replaceStrings [ "if __name__ == '__main__':\n    sys.exit(main(sys.argv))\n" ] [ "" ]
      (builtins.readFile ./butler-builders/builders.py);

  work =
    pkgs.writers.writePython3Bin "butler-work"
      {
        flakeIgnore = [
          "E501"
          "E402"
          "E302"
          "E303"
          "E305"
        ];
      }
      (
        builtins.replaceStrings (lib.attrNames substitutions) (lib.attrValues substitutions) (
          builders + builtins.readFile ./butler-builders/work.py
        )
      );
in
{
  options.butler.work.snapshot = lib.mkOption {
    description = "The Work in flight snapshot the life explorer's Changes in flight section reads, readable by the group butler.";
    type = lib.types.str;
    default = "${state}/work.json";
    readOnly = true;
  };

  config = {
    # Titles, plain summaries, states and account usage for Aaron's Work in flight view, next to the builders digest.
    systemd.services.butler-work = {
      description = "Write the Work in flight snapshot of butler's changes for the life explorer";
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = lib.getExe work;
        Group = "butler";
        StateDirectory = "butler-work";
        # Sticky and group-writable, so butler's sessions write their own files here while this snapshot and its cache stay root's.
        StateDirectoryMode = "1770";
        Environment = [ "WORK_DIRECTORY=${state}" ];
        ProtectHome = true;
        ProtectSystem = "strict";
        PrivateTmp = true;
        ReadWritePaths = [ state ];
        TimeoutStartSec = "3min";
      };
    };

    # The daemon's desk lists the changes in flight beside its sessions, reading the snapshot, and its sessions write their own work files beside it; the snapshot stays mode 640 and the cache mode 700, both root's.
    butler.writePaths = [ state ];
    systemd.services.butler.environment.DISCORD_DESK_CHANGES_FILE = "${state}/work.json";

    systemd.timers.butler-work = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnActiveSec = "1min";
        OnUnitInactiveSec = "2min";
      };
    };
  };
}
