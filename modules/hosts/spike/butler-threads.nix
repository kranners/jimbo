{
  config,
  lib,
  pkgs,
  ...
}:
let
  state = "/var/lib/butler-threads";
  discord = "${config.users.users.butler.home}/.claude/channels/discord";

  threads = pkgs.writers.writePython3Bin "butler-threads" {
    flakeIgnore = [ "E501" ];
  } (builtins.readFile ./butler-threads/threads.py);
in
{
  options.butler.threads.snapshot = lib.mkOption {
    description = "The snapshot of butler's Discord threads the life explorer's Threads tab reads, readable by the group butler.";
    type = lib.types.str;
    default = "${state}/threads.json";
    readOnly = true;
  };

  config = {
    # Every thread the daemon knows, by name, kind, times and state alone, for Aaron's Threads view in the life explorer.
    systemd.services.butler-threads = {
      description = "Write the snapshot of butler's Discord threads for the life explorer";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${lib.getExe threads} ${discord}/threads.db ${config.butler.threads.snapshot}";
        # As butler, the database's owner, so a -shm file this opens is never one the daemon cannot.
        User = "butler";
        Group = "butler";
        UMask = "0027";
        StateDirectory = "butler-threads";
        StateDirectoryMode = "0750";
        ProtectHome = true;
        ProtectSystem = "strict";
        PrivateTmp = true;
        PrivateNetwork = true;
        # Opening a WAL database, even read-only, may create its -shm file, which needs the directory writable.
        ReadWritePaths = [
          state
          "-${discord}"
        ];
        TimeoutStartSec = "1min";
      };
    };

    systemd.timers.butler-threads = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnActiveSec = "1min";
        OnUnitInactiveSec = "2min";
      };
    };
  };
}
