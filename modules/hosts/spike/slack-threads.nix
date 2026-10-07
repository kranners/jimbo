{ pkgs, ... }:
let
  home = "/home/aaron";
  checkout = "${home}/workspace/claude-slack-threads";

  slack-threads-pull = pkgs.writeShellApplication {
    name = "slack-threads-pull";
    runtimeInputs = [
      pkgs.git
      pkgs.openssh
    ];
    text = ''
      [ "$(git symbolic-ref --short HEAD)" = main ] || exit 0
      before=$(git rev-parse HEAD)
      git pull --ff-only --quiet
      [ "$(git rev-parse HEAD)" = "$before" ] || /run/wrappers/bin/sudo systemctl restart slack-threads
    '';
  };
in
{
  environment.systemPackages = [ pkgs.nodejs_24 ];

  systemd.services.slack-threads = {
    description = "Slack threads for Claude Code";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];

    path = [
      "/run/wrappers"
      "/run/current-system/sw"
      "/etc/profiles/per-user/aaron"
    ];

    environment = {
      CLAUDE_CODE_EXECUTABLE = "${pkgs.claude-code}/bin/claude";
      DISABLE_AUTOUPDATER = "1";
      SLACK_WORKER_CWD = "${home}/workspace";
      OTEL_SERVICE_NAME = "slack-threads";
    };

    serviceConfig = {
      User = "aaron";
      WorkingDirectory = checkout;
      ExecStartPre = "${pkgs.nodejs_24}/bin/npm ci --omit=dev";
      ExecStart = "${pkgs.nodejs_24}/bin/node src/slack-daemon.ts";
      Restart = "always";
      RestartSec = 10;
      TimeoutStopSec = 20;
    };
  };

  systemd.services.slack-threads-pull = {
    description = "Pull claude-slack-threads' main and restart slack-threads when it moved";
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    unitConfig.ConditionPathExists = "${checkout}/.git";
    serviceConfig = {
      Type = "oneshot";
      User = "aaron";
      WorkingDirectory = checkout;
      ExecStart = "${slack-threads-pull}/bin/slack-threads-pull";
    };
  };

  systemd.timers.slack-threads-pull = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2min";
      OnUnitInactiveSec = "2min";
    };
  };
}
