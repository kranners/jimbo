{ config, pkgs, ... }:
let
  runnerHome = config.users.users.backlogic-runner.home;
  python = pkgs.python3;
  sweep = mode: "${python}/bin/python3 -I ${./backlogic-sweep/sweep.py} ${mode}";
in
{
  # A read-only sweep of Aaron's backlogic every 10 minutes: the runner already releases,
  # re-queues and hands on a broken session itself, so this counts what that leaves, for
  # Grafana's Spike / Backlogic dashboard and one DM per batch of tickets newly needing Aaron.
  # It reads with the runner's own token and GitHub login, changing no ticket and no branch.
  systemd.services.backlogic-sweep = {
    description = "Count broken, parked and stale backlogic tickets and unlanded branches";
    after = [ "backlogic-aaron.service" ];
    unitConfig.ConditionPathExists = "${runnerHome}/runner.token";
    path = [
      pkgs.git
      "/run/current-system/sw"
    ];
    environment.HOME = runnerHome;
    serviceConfig = {
      Type = "oneshot";
      User = "backlogic-runner";
      Nice = 15;
      IOSchedulingClass = "idle";
      StateDirectory = [
        "backlogic-sweep"
        "claude-limits"
      ];
      ExecStart = sweep "sweep";
      # As root, since butler-notify's spool takes only its group; it reads ticket ids alone
      # from the runner's file, so a runner session can send Aaron nothing of its own.
      ExecStartPost = "+${sweep "notify"}";
    };
  };

  systemd.tmpfiles.rules = [ "d /var/lib/backlogic-sweep-notify 0700 root root -" ];

  systemd.timers.backlogic-sweep = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "5min";
      OnUnitInactiveSec = "10min";
    };
  };
}
