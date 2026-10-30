{ config, pkgs, ... }:
let
  inherit (config.users.users.butler) home;
  checkout = "${home}/claude-discord-threads";
  workspace = "${home}/workspace";
  secrets = "/var/lib/secrets/butler.env";
  deployKey = "${home}/.ssh/claude-discord-threads-deploy";

  readOnlySettings = pkgs.writeText "butler-claude-settings.json" (
    builtins.toJSON {
      permissions.deny = [
        "Bash"
        "Edit"
        "Write"
        "NotebookEdit"
      ];
    }
  );

  butler-pull = pkgs.writeShellApplication {
    name = "butler-pull";
    runtimeInputs = [
      pkgs.git
      pkgs.openssh
    ];
    text = ''
      [ "$(git symbolic-ref --short HEAD)" = main ] || exit 0
      before=$(git rev-parse HEAD)
      git pull --ff-only --quiet
      [ "$(git rev-parse HEAD)" = "$before" ] || touch "$RUNTIME_DIRECTORY/moved"
    '';
  };

  butler-restart-if-moved = pkgs.writeShellApplication {
    name = "butler-restart-if-moved";
    runtimeInputs = [ config.systemd.package ];
    text = ''
      [ ! -e "$RUNTIME_DIRECTORY/moved" ] || systemctl restart butler
    '';
  };
in
{
  users.users.butler = {
    isSystemUser = true;
    group = "butler";
    home = "/var/lib/butler";
    createHome = true;
  };
  users.groups.butler = { };

  systemd.tmpfiles.rules = [
    "d ${workspace} 0700 butler butler -"
    "d ${home}/.claude 0700 butler butler -"
    "L+ ${home}/.claude/settings.json - - - - ${readOnlySettings}"
  ];

  systemd.services.butler = {
    description = "Butler, Aaron's personal Discord threads for Claude Code";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    unitConfig.ConditionPathExists = [
      secrets
      "${checkout}/.git"
    ];

    path = [
      pkgs.git
      pkgs.openssh
      pkgs.nodejs_24
    ];

    environment = {
      CLAUDE_CODE_EXECUTABLE = "${pkgs.claude-code}/bin/claude";
      DISABLE_AUTOUPDATER = "1";
      DISCORD_WORKER_CWD = workspace;
      DISCORD_MAX_WORKERS = "2";
      CLAUDE_CODE_ENABLE_TELEMETRY = "1";
      OTEL_METRICS_EXPORTER = "otlp";
      OTEL_EXPORTER_OTLP_METRICS_PROTOCOL = "http/protobuf";
      OTEL_EXPORTER_OTLP_METRICS_ENDPOINT = "http://localhost:9090/api/v1/otlp/v1/metrics";
      OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE = "cumulative";
      OTEL_SERVICE_NAME = "butler";
    };

    serviceConfig = {
      User = "butler";
      WorkingDirectory = checkout;
      EnvironmentFile = secrets;
      ExecStartPre = "${pkgs.nodejs_24}/bin/npm ci --omit=dev";
      ExecStart = "${pkgs.nodejs_24}/bin/node src/daemon.ts";
      Restart = "always";
      RestartSec = 10;
      TimeoutStopSec = 20;
      OOMPolicy = "continue";
      MemoryHigh = "2G";
      MemoryMax = "3G";
      MemorySwapMax = "1G";
      ProtectHome = true;
      ProtectSystem = "strict";
      ReadWritePaths = [ home ];
      PrivateTmp = true;
      NoNewPrivileges = true;
    };
  };

  systemd.services.butler-pull = {
    description = "Pull butler's claude-discord-threads main and restart butler when it moved";
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    unitConfig.ConditionPathExists = "${checkout}/.git";
    environment.GIT_SSH_COMMAND = "ssh -i ${deployKey} -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new";
    serviceConfig = {
      Type = "oneshot";
      User = "butler";
      WorkingDirectory = checkout;
      RuntimeDirectory = "butler-pull";
      ExecStart = "${butler-pull}/bin/butler-pull";
      ExecStartPost = "+${butler-restart-if-moved}/bin/butler-restart-if-moved";
    };
  };

  systemd.timers.butler-pull = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2min";
      OnUnitInactiveSec = "2min";
    };
  };
}
