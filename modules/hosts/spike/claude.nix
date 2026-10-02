{ pkgs, ... }:
{
  environment.systemPackages = [ pkgs.claude-code ];

  # Login, the Remote Control opt-in, and trusting ~/workspace each need a TTY,
  # so they are done once by hand over SSH:
  #   claude auth login
  #   cd ~/workspace && claude remote-control
  systemd.services.claude-remote-control = {
    description = "Claude Code Remote Control server";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];

    path = [
      "/run/wrappers"
      "/run/current-system/sw"
    ];

    environment.DISABLE_AUTOUPDATER = "1";

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
