# Pulse's usage governor: every 5 minutes, with no model, it reads each Claude account's weekly and session limits
# from Prometheus, where claude-limits' textfiles land, projects each week to its reset from the burn it learnt by hour
# of the week, and writes to /var/lib/pulse-governor/governor.json how much of each would go to waste, the order new
# sessions should start on, the backlogic runner's account ceilings and which of butler's memory's token sinks the
# spare budget covers. It acts on none of it: Butler, the conductor and later changes read it.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.spike.pulseGovernor;
  state = "/var/lib/pulse-governor";
  sinksSource = "${config.users.users.butler.home}/memory/pulse/sinks";
  sinks = "/run/pulse-governor/sinks";

  python = pkgs.python3.withPackages (ps: [
    ps.pyyaml
    ps.tzdata
  ]);

  settings = pkgs.writeText "pulse-governor.json" (
    builtins.toJSON (
      cfg.settings
      // {
        state = "${state}/governor.json";
        inherit sinks;
        timezone = config.time.timeZone;
        runnerSessions = config.backlogicRunner.gates.sessions or 64;
      }
    )
  );

  # `pulse-governor status`, `json` and `sinks` read the state file, which anyone may; `run` is the unit's.
  cli = pkgs.writeShellApplication {
    name = "pulse-governor";
    text = ''
      export PULSE_GOVERNOR_CONFIG=''${PULSE_GOVERNOR_CONFIG:-${settings}}
      exec ${python}/bin/python3 -I ${./pulse-governor/governor.py} "$@"
    '';
  };
in
{
  options.spike.pulseGovernor = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Run pulse's usage governor, which projects each Claude account to its reset and ranks the token sinks.";
    };

    settings = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      example = {
        floorMax = 15;
        releaseWindowHours = 24;
      };
      description = "Overrides of governor.py's DEFAULTS, such as the interactive floor or the release window.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cli ];

    systemd.services.pulse-governor = {
      description = "Project each Claude account's usage to its reset and rank the token sinks";
      after = [ "prometheus.service" ];
      environment.PULSE_GOVERNOR_CONFIG = "${settings}";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${lib.getExe cli} run";
        User = "pulse";
        Group = "pulse";
        StateDirectory = "pulse-governor";
        StateDirectoryMode = "0755";
        RuntimeDirectory = "pulse-governor";
        # The sinks alone of butler's memory, read-only, and nothing when that folder is not there yet.
        BindReadOnlyPaths = [ "-${sinksSource}:${sinks}" ];
        Nice = 10;
        CPUWeight = 20;
        IOWeight = 20;
        MemoryMax = "200M";

        # Prometheus on loopback is all it talks to.
        IPAddressAllow = "localhost";
        IPAddressDeny = "any";
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
        ];
        NoNewPrivileges = true;
        CapabilityBoundingSet = "";
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
        SystemCallArchitectures = "native";
        SystemCallFilter = [
          "@system-service"
          "~@privileged"
        ];
      };
    };

    systemd.timers.pulse-governor = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "3min";
        OnUnitActiveSec = "5min";
      };
    };
  };
}
