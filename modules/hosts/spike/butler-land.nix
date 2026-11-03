# butler's landing queue: a deploy that would restart butler, or the speech services its calls use,
# waits while Aaron is on a call and goes out on a cue (butler-land/land.py says how).
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkOption types;
  cfg = config.butler.land;

  state = "/var/lib/butler-land";
  # butler's own runtime directory, where the daemon keeps the call state; gone while butler is stopped, which reads as no call.
  callDir = "/run/butler-call";

  butler-land = pkgs.writeShellApplication {
    name = "butler-land";
    runtimeInputs = [ config.systemd.package ];
    text = ''
      export LAND_STATE=${state}
      export LAND_CALL_STATE=${callDir}/call.json
      export LAND_QUIET_S=${toString cfg.quietSeconds}
      export LAND_MAX_HOLD_S=${toString (cfg.maxHoldMinutes * 60)}
      export LAND_SAY=/run/current-system/sw/bin/butler-call-say
      export LAND_NOTIFY=/run/current-system/sw/bin/butler-notify
      exec ${pkgs.python3}/bin/python3 -I ${./butler-land/land.py} "$@"
    '';
  };

  # butler's command and /land's: Aaron's words alone, never the internal verbs.
  land-queue = pkgs.writeShellApplication {
    name = "land-queue";
    text = ''
      usage() {
        echo "usage: land-queue [status | now | hold | release | when-quiet | at HH:MM | on | off | always]" >&2
        exit 2
      }
      case "''${1:-status}" in
        status | now | hold | release | when-quiet | on | off | always) [ "$#" -le 1 ] || usage ;;
        at) [ "$#" -eq 2 ] || usage ;;
        *) usage ;;
      esac
      exec ${lib.getExe butler-land} "$@"
    '';
  };

  everyLane = [
    "interactive"
    "cron"
    "call"
  ];
  steer = word: {
    match = [ word ];
    lanes = [ "interactive" ];
  };
in
{
  options.butler.land = {
    quietSeconds = mkOption {
      type = types.ints.positive;
      default = 20;
      description = "How long a live call must go without speech, audio or a working turn before a held landing goes.";
    };
    maxHoldMinutes = mkOption {
      type = types.ints.positive;
      default = 30;
      description = "The longest a landing waits, unless Aaron set a later time with `at`.";
    };
    restartUnits = mkOption {
      type = types.listOf types.str;
      default = [
        "butler.service"
        "wyoming-faster-whisper-en.service"
        "wyoming-kokoro.service"
      ];
      description = "Units whose restart drops or cuts into a call: a switch that changes any of them is held while a call is live.";
    };
    package = mkOption {
      type = types.package;
      readOnly = true;
      internal = true;
      default = butler-land;
      description = "`butler-land`, for jimbo-switch and butler-pull to gate their deploys through.";
    };
  };

  config = {
    butler.commands.land-queue = {
      package = land-queue;
      description = ''
        The landing queue: deploys that would restart butler wait while Aaron is on a call, then land at a quiet moment, when the call ends, at a time he names or after 30 minutes, with a shout before.
        land-queue [status] (what is waiting, its fixes, when each landed and what it would restart) | now (land everything waiting at once, or the next landing within 15 minutes) | hold (hold until released) | release or when-quiet (back to the quiet cue) | at HH:MM | on (hold only during calls, the default) | off (never hold) | always (hold even with no call)
      '';
      rules = [
        {
          match = [ ];
          lanes = everyLane;
        }
        {
          match = [ "status" ];
          lanes = everyLane;
        }
        (steer "now")
        (steer "hold")
        (steer "release")
        (steer "when-quiet")
        (steer "on")
        (steer "off")
        (steer "always")
        {
          match = [
            "at"
            "*"
          ];
          lanes = [ "interactive" ];
        }
      ];
      skill = ./butler-skills/land-queue;
    };

    systemd.tmpfiles.rules = [ "d ${state} 2770 root butler-notify -" ];

    environment.systemPackages = [ land-queue ];

    systemd.services.butler = {
      environment = {
        DISCORD_CALL_STATE_FILE = "${callDir}/call.json";
        DISCORD_LAND_COMMAND = lib.getExe land-queue;
      };
      serviceConfig = {
        RuntimeDirectory = baseNameOf callDir;
        RuntimeDirectoryMode = "0755";
        BindPaths = [ state ];
      };
    };

    # Runs only while something is held, so an empty queue costs nothing.
    systemd.paths.butler-land = {
      wantedBy = [ "paths.target" ];
      pathConfig.PathExists = "${state}/queue.json";
    };

    systemd.services.butler-land = {
      description = "Release held landings on their cue: a quiet call, its end, Aaron's word, his time or the longest hold";
      # A switch it released must never stop it midway.
      restartIfChanged = false;
      serviceConfig = {
        Type = "simple";
        ExecStart = "${lib.getExe butler-land} watch";
      };
    };
  };
}
