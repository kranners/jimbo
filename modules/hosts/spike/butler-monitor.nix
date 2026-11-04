{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkOption types;
  cfg = config.butler.monitor;
  defaults = import ./butler-monitor/defaults.nix;
  state = "/var/lib/butler-monitor";
  control = "/var/lib/butler-monitor-control";

  peer =
    name: lib.findFirst (peer: peer.name == name) null config.networking.wireguard.interfaces.wg0.peers;
  addressOf = name: lib.removeSuffix "/32" (lib.head (peer name).allowedIPs);

  # The machines reached over ssh with butler's Mac key, as `mac` reaches them; spike and framer come from Prometheus.
  hosts = {
    pilot = {
      os = "macos";
      address = addressOf "pilot";
      user = "aaronpierce";
    };
    piggys-MBP = {
      os = "macos";
      address = addressOf "piggys-MBP";
      user = "aaron";
    };
    jimbo.systems =
      lib.optional (peer "jimbo" != null) {
        os = "linux";
        address = addressOf "jimbo";
        user = "aaron";
      }
      ++ [
        {
          os = "windows";
          address = addressOf "windows";
          user = "aaron";
        }
      ];
  };

  monitorConfig = {
    inherit state hosts;
    inherit (cfg)
      thresholds
      alwaysOn
      keepAwakeHosts
      readOnlyHosts
      defaultMode
      keepGenerations
      journalVacuum
      snapshot
      holdFile
      ;
    control = "${control}/mode";
    # Machines meant to be off, one JSON file each, written by butler's `monitor expect` and `mac`'s sleep and boot.
    expected = cfg.expectedDir;
    textfile = "/var/lib/claude-limits/butler-monitor.prom";
    prometheus = "http://127.0.0.1:${toString config.services.prometheus.port}";
    prometheusHosts = [
      "spike"
      "framer"
    ];
    work = config.butler.work.snapshot;
    # The daemon's call state file, which carries its turn pool, and the back-off file it reads.
    callState = "/run/butler-call/call.json";
    inherit (cfg) backoffFile;
    limits = "/var/lib/claude-limits";
    outbox = "${config.users.users.butler.home}/outbox";
    group = "butler";
    quiet = cfg.quietHours;
    # Failed units of butler's own a run may restart once; never the daemon, its restarters, the landing queue or a change launch.
    restartable = "butler-[a-z0-9-]+\\.service";
    neverRestart = [
      "butler.service"
      "butler-self-fix.service"
      "butler-restart.service"
      "butler-restart-overdue.service"
      "butler-land.service"
      "butler-monitor.service"
    ];
    # Every failed unit is judged from its own journal, by unitFailRuns, unitFailedMinutes and unitFailsPerDay; these
    # set a unit's own bar of failed runs in a row, a count the unit keeps itself in file, believed when it says
    # more, and how long one run may go before it counts as stuck.
    failStreaks."backlogic-switch.service" = {
      file = "/var/lib/backlogic-switch/failed-runs";
      runs = 3;
      stuckMinutes = 10;
    };
    ssh = lib.getExe pkgs.openssh;
    docker = "${config.virtualisation.docker.package}/bin/docker";
    nixEnv = "${config.nix.package}/bin/nix-env";
    nixStore = "${config.nix.package}/bin/nix-store";
    journalctl = "${config.systemd.package}/bin/journalctl";
    systemctl = "${config.systemd.package}/bin/systemctl";
    tmpfiles = "${config.systemd.package}/bin/systemd-tmpfiles";
    notify = "/run/current-system/sw/bin/butler-notify";
    callSay = "/run/current-system/sw/bin/butler-call-say";
  };

  configFile = pkgs.writeText "butler-monitor.json" (builtins.toJSON monitorConfig);

  monitor = pkgs.writers.writePython3Bin "butler-monitor" {
    flakeIgnore = [
      "E501"
      "W503"
      "W504"
    ];
  } (builtins.readFile ./butler-monitor/monitor.py);

  # butler's view: the status and log to read, and the act switch to set, which only Aaron's words reach.
  command = pkgs.writeShellApplication {
    name = "monitor";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.jq
    ];
    text = ''
      mode() { cat ${control}/mode 2> /dev/null || echo "${cfg.defaultMode} (the default)"; }
      notices() {
        [ -f ${state}/notices.jsonl ] || { echo "Nothing seen yet."; exit 0; }
        jq -r "$1"' | "\(.at | strflocaltime("%a %d %b %H:%M")) [\(.route)\(if .why then ": " + .why else "" end)] \(.text)"' ${state}/notices.jsonl | tail -n 30
      }
      if [ "''${1:-}" = expect ]; then
        shift
        MONITOR_CONFIG=${configFile} exec ${lib.getExe monitor} expect "$@"
      fi
      case "''${1:-status} ''${2:-}" in
        "status ")
          cat ${state}/status.txt 2> /dev/null || echo "The monitor has not run yet."
          [ ! -e ${cfg.holdFile} ] || echo "New change sessions and runner launches are held: $(cat ${cfg.holdFile})"
          ;;
        "log ") notices 'select(true)' ;;
        "log quiet") notices 'select(.route != "told")' ;;
        "log actions")
          [ -f ${state}/actions.jsonl ] || { echo "Nothing done or planned yet."; exit 0; }
          tail -n 20 ${state}/actions.jsonl | jq -r '"\(.at | strflocaltime("%a %d %b %H:%M")) [\(.result)] \(.line)"'
          ;;
        "act ") echo "Acting is $(mode). on takes the safe steps, dry-run only says what it would do, off neither." ;;
        "act on" | "act off" | "act dry-run")
          printf '%s\n' "$2" > ${control}/mode.tmp
          mv ${control}/mode.tmp ${control}/mode
          echo "Acting is now $2, from the monitor's next run within 2 minutes; warnings carry on either way."
          ;;
        *)
          echo "usage: monitor [status] | monitor log [quiet|actions] | monitor expect [<host> [clear | [down] [until HH:MM | for <N>h] [reason]]] | monitor act [on|off|dry-run]" >&2
          exit 2
          ;;
      esac
    '';
  };

  reads = [
    "interactive"
    "cron"
    "call"
  ];
in
{
  options.butler.monitor = {
    enable = mkOption {
      description = "Whether butler-monitor watches the machines and resources every 2 minutes.";
      type = types.bool;
      default = true;
    };
    defaultMode = mkOption {
      description = "Acting before Aaron chooses with `monitor act`: dry-run logs and reports what it would do.";
      type = types.enum [
        "on"
        "off"
        "dry-run"
      ];
      default = "dry-run";
    };
    thresholds = mkOption {
      description = "Every limit the monitor judges by, in one place.";
      type = types.attrsOf types.number;
      # Pruned after every switch, so a few more than the keep-count means pruning stopped.
      default = defaults.thresholds // {
        maxGenerations = config.jimbo.keepGenerations + 2;
      };
    };
    alwaysOn = mkOption {
      description = "Machines whose being down is urgent, told once and again only as still open after a day; any other being down is only logged.";
      type = types.listOf types.str;
      default = [
        "spike"
        "framer"
      ];
    };
    keepAwakeHosts = mkOption {
      description = "Machines whose keep-awake the monitor turns back on when acting.";
      type = types.listOf types.str;
      default = [
        "piggys-MBP"
        "jimbo"
      ];
    };
    readOnlyHosts = mkOption {
      description = "Machines the monitor only reads, never acts on: pilot is Aaron's employer's.";
      type = types.listOf types.str;
      default = [ "pilot" ];
    };
    quietHours = mkOption {
      description = "Between start and end only urgent notices go out; the rest wait for a summary at summary.";
      type = types.attrsOf types.str;
      default = defaults.quiet;
    };
    keepGenerations = mkOption {
      type = types.int;
      default = config.jimbo.keepGenerations;
    };
    journalVacuum = mkOption {
      type = types.str;
      default = "500M";
    };
    snapshot = mkOption {
      description = "The Machines snapshot, plain lines per machine and the open problems, readable by the group butler.";
      type = types.str;
      default = "${state}/machines.json";
      readOnly = true;
    };
    backoffFile = mkOption {
      description = "Whether butler should run fewer turns at once, written every run from claude-limits, the daemon's DISCORD_LIMITS_FILE.";
      type = types.str;
      default = "${state}/concurrency.json";
      readOnly = true;
    };
    expectedDir = mkOption {
      description = "Machines meant to be off, one JSON file each, which butler's `monitor expect` and `mac`'s sleep, keep-awake off and boot write.";
      type = types.str;
      default = "${control}/expected";
      readOnly = true;
    };
    holdFile = mkOption {
      description = "Present while the monitor, acting, holds new change sessions and runner launches.";
      type = types.str;
      default = "${state}/hold";
      readOnly = true;
    };
  };

  config = lib.mkIf cfg.enable {
    butler.commands.monitor = {
      package = command;
      description = ''
        The machines monitor: what spike, framer, piggys-MBP, pilot and jimbo look like now and the problems open, from its last run within 2 minutes, and what it saw but did not tell Aaron.
        monitor [status] | monitor log [quiet|actions] (the last 30 things it saw and what it did with each; quiet is only what it did not tell Aaron; actions the last 20 it did or would have done) | monitor expect [<host> [clear | [down] [until HH:MM | for <N>h] [reason]]] (mark a machine meant to be off, so nothing is said about it) | monitor act [on|off|dry-run] (on only when Aaron himself says so)
      '';
      rules = [
        {
          match = [ ];
          lanes = reads;
        }
        {
          match = [ "status" ];
          lanes = reads;
        }
        {
          match = [ "log" ];
          lanes = reads;
        }
        {
          match = [
            "log"
            "quiet"
          ];
          lanes = reads;
        }
        {
          match = [
            "log"
            "actions"
          ];
          lanes = reads;
        }
        {
          match = [ "expect" ];
          lanes = reads;
        }
        # A mark only keeps the monitor quieter about one machine for at most a week.
        {
          match = [
            "expect"
            "**"
          ];
          lanes = [
            "interactive"
            "cron"
          ];
          acts = true;
        }
        {
          match = [ "act" ];
          lanes = reads;
        }
        # Turning acting on always waits for Aaron's button, as a sending command does.
        {
          match = [
            "act"
            "on"
          ];
          lanes = [ "interactive" ];
          taints = true;
          egress = true;
        }
        {
          match = [
            "act"
            "off"
          ];
          lanes = [ "interactive" ];
          acts = true;
        }
        {
          match = [
            "act"
            "dry-run"
          ];
          lanes = [ "interactive" ];
          acts = true;
        }
      ];
      skill = ./butler-skills/monitor;
    };

    systemd.tmpfiles.rules = [
      "d ${state} 0750 root butler -"
      "d ${control} 2770 root butler -"
      "d ${cfg.expectedDir} 2770 root butler -"
    ];

    systemd.services.butler = {
      environment.DISCORD_LIMITS_FILE = cfg.backoffFile;
      serviceConfig = {
        BindReadOnlyPaths = [ "-${state}" ];
        BindPaths = [ "-${control}" ];
      };
    };

    # One run collects every machine with short ssh connections, judges, acts or logs what it would, and notifies.
    systemd.services.butler-monitor = {
      description = "Watch Aaron's machines and resources, notify through butler and take only safe steps";
      wants = [ "network-online.target" ];
      after = [
        "network-online.target"
        "prometheus.service"
      ];
      path = [
        pkgs.coreutils
        pkgs.findutils
      ];
      environment.MONITOR_CONFIG = configFile;
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${lib.getExe monitor} run";
        LoadCredential = [ "butler-mac-key:/var/lib/secrets/butler-mac-key" ];
        Nice = 10;
        IOSchedulingClass = "idle";
        TimeoutStartSec = "45min";
      };
    };

    systemd.timers.butler-monitor = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "3min";
        OnUnitInactiveSec = "2min";
      };
    };
  };
}
