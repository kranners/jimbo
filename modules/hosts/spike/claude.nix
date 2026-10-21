{ pkgs, ... }:
{
  # Claude Code hooks in repositories here, such as backlogic's guards, run with python3.
  # backlogic's bin/check and board publishing load boards in a headless Chrome found on PATH.
  environment.systemPackages = [
    pkgs.claude-code
    pkgs.python3
    pkgs.google-chrome
  ];

  # Login, the Remote Control opt-in, and trusting ~/workspace each need a TTY,
  # so they are done once by hand over SSH:
  #   claude auth login
  #   CLAUDE_CONFIG_DIR=~/.claude-work claude auth login
  #   cd ~/workspace && CLAUDE_CONFIG_DIR=~/.claude-work claude remote-control
  systemd.services.claude-remote-control = {
    description = "Claude Code Remote Control server";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];

    path = [
      "/run/wrappers"
      "/run/current-system/sw"
    ];

    environment = {
      CLAUDE_CONFIG_DIR = "/home/aaron/.claude-work";
      DISABLE_AUTOUPDATER = "1";
      OTEL_SERVICE_NAME = "remote-control";
    };

    serviceConfig = {
      User = "aaron";
      WorkingDirectory = "/home/aaron/workspace";
      ExecStart = "${pkgs.claude-code}/bin/claude remote-control --name spike --spawn same-dir";

      # Server mode exits after about ten minutes offline. Restarting in the
      # same directory resumes the sessions it was serving.
      Restart = "always";
      RestartSec = 10;
    };
  };
}
