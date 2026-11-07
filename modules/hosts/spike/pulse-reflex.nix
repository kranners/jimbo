# The one root channel pulse's reflexes act through, so pulse itself runs unprivileged: a reflex drops a request into
# the spool's requests/, and pulse-reflex-act.path runs pulse-reflex-act.service as root, which carries out only the
# fixed actions of pulse-reflex/act.py on the targets allowed below, never the monitor's protected units, refuses all
# of them while `pulse reflex off` or `monitor act off` holds, and writes each result back for pulse to verify.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.spike.pulseReflex;
  spool = "/var/lib/pulse-reflex";
  state = "/var/lib/pulse-reflex-act";
  monitorDefaults = import ./butler-monitor/defaults.nix;

  peer =
    name: lib.findFirst (peer: peer.name == name) null config.networking.wireguard.interfaces.wg0.peers;
  addressOf = name: lib.removeSuffix "/32" (lib.head (peer name).allowedIPs);

  actConfig = {
    inherit spool state;
    inherit (cfg)
      units
      stateFiles
      perTargetPerHour
      perHour
      stuckSeconds
      settleSeconds
      macFreeFloor
      ;
    macs = lib.genAttrs cfg.macs (name: {
      address = addressOf name;
      user = "aaron";
    });
    macTimeout = 600;
    perMinute = 20;
    # The monitor's known_hosts, whose Mac keys it has already trusted, read only, so no key is trusted here anew.
    knownHosts = "/var/lib/butler-monitor/known_hosts";
    macScript = builtins.readFile ./pulse-reflex/mac-free-disk.sh;
    protect = monitorDefaults.remediation.protect;
    monitorMode = "/var/lib/butler-monitor-control/mode";
    systemctl = "${config.systemd.package}/bin/systemctl";
    ssh = lib.getExe pkgs.openssh;
  };

  act = pkgs.writers.writePython3Bin "pulse-reflex-act" {
    flakeIgnore = [ "E501" ];
  } (builtins.readFile ./pulse-reflex/act.py);
in
{
  options.spike.pulseReflex = {
    group = lib.mkOption {
      description = "The group whose members may drop requests into the spool and read results: pulse's service joins it.";
      type = lib.types.str;
      default = "pulse-reflex";
      readOnly = true;
    };
    spool = lib.mkOption {
      description = "The spool: requests/<id>.json in, results/<id>.json out, and `off`, pulse's kill switch.";
      type = lib.types.str;
      default = spool;
      readOnly = true;
    };
    units = lib.mkOption {
      description = ''
        Units, as regexes matched whole, each action may touch: `start` a failed one, `restart` one stuck activating,
        `timer` the failed service of a timer, `run` an idle oneshot now; the monitor's protect list always wins.
      '';
      type = lib.types.attrsOf (lib.types.listOf lib.types.str);
      default = rec {
        start = [
          "backlogic-runner-aaron\\.service"
          "backlogic-runner-gates\\.service"
          "kanban\\.service"
          "kanban-bridge\\.(service|socket)"
          "bowerbird-worker\\.service"
          "bowerbird-display(@[0-9]+)?\\.service"
          "bowerbird-vnc-proxy\\.service"
          "bowerbird-sync-displays\\.service"
          "butler-memory-pull\\.service"
          "butler-feeds\\.service"
          "butler-index-[a-z0-9-]+\\.service"
          "butler-remarkable-sync\\.service"
        ];
        restart = map (u: if lib.hasInfix "socket" u then "kanban-bridge\\.service" else u) start;
        timer = [
          "butler-memory-pull\\.service"
          "butler-feeds\\.service"
          "butler-index-[a-z0-9-]+\\.service"
          "butler-remarkable-sync\\.service"
          "butler-(kanban-[a-z-]+|jobs|context|builders|work|threads)\\.service"
          "bowerbird-sync-displays\\.service"
          "backlogic-sweep\\.service"
          "claude-limits\\.service"
        ];
        run = [ "butler-kanban-safe-prompts\\.service" ];
      };
    };
    stateFiles = lib.mkOption {
      description = "State files, by path, whose owner's write bit may be given back, each with the unit it blocks.";
      type = lib.types.attrsOf lib.types.str;
      default."/var/lib/backlogic-runner-gates/applied.json" = "backlogic-runner-gates.service";
    };
    macs = lib.mkOption {
      description = "Macs whose caches may be cleared under their free-disk floor; never pilot, the employer's.";
      type = lib.types.listOf (lib.types.enum [ "piggys-MBP" ]);
      default = [ "piggys-MBP" ];
    };
    macFreeFloor = lib.mkOption {
      description = "The percent of a Mac's disk free under which its caches may be cleared.";
      type = lib.types.ints.between 1 50;
      default = 15;
    };
    perTargetPerHour = lib.mkOption {
      description = "This channel's own ceiling on actions of any kind on one target in an hour, under pulse's own limits.";
      type = lib.types.ints.positive;
      default = 3;
    };
    perHour = lib.mkOption {
      description = "This channel's own ceiling on actions in all in an hour.";
      type = lib.types.ints.positive;
      default = 30;
    };
    stuckSeconds = lib.mkOption {
      description = "How long a unit must have sat activating before it counts as stuck.";
      type = lib.types.ints.positive;
      default = 600;
    };
    settleSeconds = lib.mkOption {
      description = "How long the channel waits for a unit it started to settle before writing its result.";
      type = lib.types.ints.positive;
      default = 90;
    };
  };

  config = {
    users.groups.${cfg.group} = { };

    systemd.tmpfiles.rules = [
      # Sticky, so a member can add files beside requests/ and results/ but never rename or remove them.
      "d ${spool} 3770 root ${cfg.group} -"
      # pulse writes a request in incoming/ and renames it into requests/, so a half-written one never wakes root.
      "d ${spool}/incoming 2770 root ${cfg.group} -"
      "d ${spool}/requests 2770 root ${cfg.group} -"
      "d ${spool}/results 2750 root ${cfg.group} -"
      "d ${state} 0700 root root -"
    ];

    # pulse writes requests and reads results as a member of the group, through a hole in its read-only filesystem.
    systemd.services.pulse = lib.mkIf config.spike.pulse.enable {
      environment.PULSE_REFLEX_SPOOL = spool;
      serviceConfig = {
        SupplementaryGroups = [ cfg.group ];
        ReadWritePaths = [ spool ];
      };
    };

    systemd.paths.pulse-reflex-act = {
      wantedBy = [ "paths.target" ];
      pathConfig.DirectoryNotEmpty = "${spool}/requests";
    };

    systemd.services.pulse-reflex-act = {
      description = "Carry out pulse's allowlisted reflex actions as root";
      unitConfig.StartLimitIntervalSec = 0;
      environment.PULSE_REFLEX_ACT_CONFIG = pkgs.writeText "pulse-reflex-act.json" (builtins.toJSON actConfig);
      path = [ pkgs.coreutils ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = lib.getExe act;
        LoadCredential = [ "butler-mac-key:/var/lib/secrets/butler-mac-key" ];
        TimeoutStartSec = "20min";
        UMask = "0027";
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        NoNewPrivileges = true;
        ReadWritePaths = [
          spool
          state
        ]
        ++ lib.unique (map (p: "-${dirOf p}") (lib.attrNames cfg.stateFiles));
      };
    };
  };
}
