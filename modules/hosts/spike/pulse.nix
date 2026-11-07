{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  cfg = config.spike.pulse;
  state = "/var/lib/pulse";
  # Butler's memory's pulse folder, bound read-only into the unit, so pulse reads the watches, goals and policy
  # butler edits and nothing else of its memory.
  memorySource = "${config.users.users.butler.home}/memory/pulse";
  memory = "/run/pulse/memory";

  environment = {
    PULSE_DB = "${state}/pulse.db";
    PULSE_MEMORY = memory;
    PULSE_LISTEN = cfg.listen;
    PULSE_HOST = config.networking.hostName;
    PULSE_AUDIT = "/var/lib/butler-audit/pulse.jsonl";
  };

  # `pulse status`, `doctor` and the rest for a login on spike: they ask the service over loopback first, and read
  # the database and the memory's files directly where the user may.
  cli = pkgs.writeShellApplication {
    name = "pulse";
    text = ''
      ${lib.concatStringsSep "\n" (
        lib.mapAttrsToList (name: value: "export ${name}=\"\${${name}:-${value}}\"") (
          environment // { PULSE_MEMORY = memorySource; }
        )
      )}
      exec ${lib.getExe cfg.package} "$@"
    '';
  };
in
{
  options.spike.pulse = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Run Pulse, butler's event-driven background service, as the system user pulse.";
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = inputs.butler.packages.${pkgs.stdenv.hostPlatform.system}.pulse;
      defaultText = lib.literalExpression "inputs.butler.packages.\${system}.pulse";
      description = "The pulse package, from the private flake.";
    };

    listen = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1:18790";
      description = "Where pulse serves /health and /metrics, loopback alone.";
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.pulse = {
      isSystemUser = true;
      group = "pulse";
      description = "Pulse, butler's background service";
    };
    users.groups.pulse = { };

    environment.systemPackages = [ cli ];

    systemd.paths.pulse = {
      wantedBy = [ "paths.target" ];
      pathConfig = {
        PathExists = memorySource;
        Unit = "pulse.service";
      };
    };

    systemd.services.pulse = {
      description = "Pulse, butler's event-driven background service";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      inherit environment;
      # The infrastructure sensors ask systemd for its units and read the journal of the units they watch.
      path = [ config.systemd.package ];
      # The bind below needs the memory's pulse folder, so pulse waits for butler-memory-pull to bring it, and
      # pulse.path starts it once it is there.
      unitConfig.ConditionPathIsDirectory = memorySource;
      serviceConfig = {
        ExecStart = "${lib.getExe cfg.package} run";
        User = "pulse";
        Group = "pulse";
        # The journal, and the group-butler snapshots other services already write for butler to read: the machines
        # monitor's machines.json, butler-work's work.json and butler-threads' threads.json. ProtectSystem=strict keeps
        # every one of them read-only to pulse, and butler's own home stays 0700, out of reach.
        SupplementaryGroups = [
          "systemd-journal"
          "butler"
        ];
        UMask = "0027";
        StateDirectory = "pulse";
        StateDirectoryMode = "0750";
        RuntimeDirectory = "pulse";
        BindReadOnlyPaths = [ "${memorySource}:${memory}" ];
        Restart = "always";
        RestartSec = "10s";

        # spike is crowded, so pulse stays small and yields to everything else.
        CPUQuota = "25%";
        MemoryHigh = "250M";
        MemoryMax = "300M";
        MemorySwapMax = "100M";
        TasksMax = 64;
        Nice = 10;
        CPUWeight = 20;
        IOWeight = 20;

        NoNewPrivileges = true;
        CapabilityBoundingSet = "";
        AmbientCapabilities = "";
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectProc = "invisible";
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectKernelLogs = true;
        ProtectControlGroups = true;
        ProtectClock = true;
        ProtectHostname = true;
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        RemoveIPC = true;
        RestrictAddressFamilies = [
          "AF_UNIX"
          "AF_INET"
          "AF_INET6"
        ];
        SystemCallArchitectures = "native";
        SystemCallFilter = [
          "@system-service"
          "~@privileged"
          "~@resources"
        ];
      };
    };
  };
}
