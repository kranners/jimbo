{ pkgs, ... }:
let
  home = "/home/aaron";
in
{
  environment.systemPackages = [ pkgs.bun ];

  systemd.services.discord-threads = {
    description = "Discord threads for Claude Code";
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
      DISCORD_WORKER_CWD = "${home}/workspace";
    };

    serviceConfig = {
      User = "aaron";
      WorkingDirectory = "${home}/workspace/claude-discord-threads";
      ExecStartPre = "${pkgs.bun}/bin/bun install --frozen-lockfile";
      ExecStart = "${pkgs.bun}/bin/bun run src/daemon.ts";
      Restart = "always";
      RestartSec = 10;
      TimeoutStopSec = 20;
    };
  };
}
