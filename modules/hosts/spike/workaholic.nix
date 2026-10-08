{ lib, pkgs, ... }:
let
  checkout = "/srv/workaholic";
  home = "/var/lib/workaholic";
  profile = "mixed";
  lanInterfaces = [
    "wlp2s0"
    "wg0"
  ];
  runners = lib.range 1 8;
  config = pkgs.writeText "workaholic-config.json" (
    builtins.toJSON {
      operator = {
        name = "Aaron";
        slackId = "U0C7EC38RA8";
      };
      projects = [
        {
          repo = "kranners/bowerbird";
          slackChannel = "C0C7G8EA66M";
        }
        {
          repo = "kranners/jimbo";
          slackChannel = "C0C88M61B4G";
        }
        {
          repo = "kranners/workaholic";
          slackChannel = "C0C7J4Y8GGL";
        }
        {
          repo = "kranners/claude-slack-threads";
          slackChannel = "C0C7G8F1WAD";
        }
      ];
      previewHosts = [
        "spike.local"
        "10.100.0.1"
      ];
      gitAuthor = {
        name = "workaholic";
        email = "workaholic@spike.local";
      };
    }
  );
  runEnvironment = {
    SHELL = "${pkgs.bashInteractive}/bin/bash";
    TEST_CHROMIUM_PATH = "${pkgs.google-chrome}/bin/google-chrome-stable";
    CLAUDE_CODE_ENABLE_TELEMETRY = "1";
    OTEL_METRICS_EXPORTER = "otlp";
    OTEL_EXPORTER_OTLP_METRICS_PROTOCOL = "http/protobuf";
    OTEL_EXPORTER_OTLP_METRICS_ENDPOINT = "http://localhost:9090/api/v1/otlp/v1/metrics";
    OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE = "cumulative";
    OTEL_SERVICE_NAME = "workaholic";
  };
  runPath = [
    pkgs.git
    pkgs.claude-code
    pkgs.nodejs_24
    pkgs.curl
  ];

  workaholic-pull = pkgs.writeShellApplication {
    name = "workaholic-pull";
    runtimeInputs = [
      pkgs.git
      pkgs.openssh
    ];
    text = ''
      before=$(git rev-parse HEAD)
      git pull --ff-only
      [ "$(git rev-parse HEAD)" = "$before" ] || /run/wrappers/bin/sudo systemctl try-restart workaholic-listen
    '';
  };
in
{
  users.users.workaholic = {
    isSystemUser = true;
    group = "workaholic";
    extraGroups = [ "bowerbird" ];
    inherit home;
    linger = true;
  };
  users.groups.workaholic = { };

  systemd.tmpfiles.rules = [
    "d ${checkout} 0755 aaron users -"
    "d ${home} 0750 workaholic workaholic -"
    "d ${home}/.config 0755 workaholic workaholic -"
    "d ${home}/.config/workaholic 0700 workaholic workaholic -"
    "L+ ${home}/.config/workaholic/config.json - - - - ${config}"
  ];

  systemd.services.workaholic-pull = {
    description = "Pull workaholic's main into ${checkout} before a run and restart workaholic-listen when it moved";
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    unitConfig.ConditionPathExists = "${checkout}/.git";
    serviceConfig = {
      Type = "oneshot";
      User = "aaron";
      WorkingDirectory = checkout;
      ExecStart = "${workaholic-pull}/bin/workaholic-pull";
    };
  };

  systemd.slices.system-workaholic.sliceConfig = {
    MemoryHigh = "7G";
    MemoryMax = "8G";
  };

  systemd.services."workaholic@" = {
    description = "workaholic runner %i, works GitHub issues within spare compute and Claude Max usage";
    wants = [
      "network-online.target"
      "workaholic-pull.service"
    ];
    after = [
      "network-online.target"
      "workaholic-pull.service"
    ];
    unitConfig.ConditionPathExists = "${checkout}/package.json";
    environment = runEnvironment;
    path = runPath;
    restartIfChanged = false;

    serviceConfig = {
      Type = "oneshot";
      User = "workaholic";
      WorkingDirectory = checkout;
      ExecStart = "${pkgs.nodejs_24}/bin/node src/run.ts --profile ${profile}";
      Nice = 10;
      CPUWeight = 20;
      IOWeight = 20;
    };
  };

  systemd.services.workaholic-listen = {
    description = "workaholic's Discord listener, for its slash commands in issue threads";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    unitConfig.ConditionPathExists = "${checkout}/src/listen.ts";
    environment = runEnvironment;
    path = runPath;
    serviceConfig = {
      User = "workaholic";
      WorkingDirectory = checkout;
      ExecStart = "${pkgs.nodejs_24}/bin/node src/listen.ts";
      Restart = "always";
      RestartSec = 10;
    };
  };

  networking.firewall.interfaces = lib.genAttrs lanInterfaces (_: {
    allowedTCPPortRanges = [
      {
        from = 4000;
        to = 4999;
      }
    ];
  });

  systemd.timers = lib.listToAttrs (
    map (runner: {
      name = "workaholic@${toString runner}";
      value = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "${toString (3 + 2 * runner)}min";
          OnUnitInactiveSec = "5min";
        };
      };
    }) runners
  );
}
