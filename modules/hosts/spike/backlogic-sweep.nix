{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.spike.backlogicSweep;
  runnerHome = config.users.users.backlogic-runner.home;
  python = pkgs.python3;
  sweep = mode: "${python}/bin/python3 -I ${./backlogic-sweep/sweep.py} ${mode}";
in
{
  options.spike.backlogicSweep.waiting = {
    days = lib.mkOption {
      type = lib.types.ints.positive;
      default = 3;
      description = "How many days a ticket must have waited on Aaron to count towards the daily notice.";
    };
    count = lib.mkOption {
      type = lib.types.ints.positive;
      default = 10;
      description = "How many tickets must have waited that long before the daily notice is sent.";
    };
  };

  # A read-only sweep of Aaron's backlogic every 10 minutes: the runner already releases,
  # re-queues and hands on a broken session itself, so this counts what that leaves, for
  # Grafana's Spike / Backlogic dashboard. Aaron asked on 5 Nov 2026 to hear only when the
  # runner is down, and when it is back, and at most daily when tickets pile up waiting on him.
  # It reads with the runner's own token and GitHub login, changing no ticket and no branch.
  config.systemd.services.backlogic-sweep = {
    description = "Count broken, parked and stale backlogic tickets and unlanded branches";
    after = [ "backlogic-aaron.service" ];
    unitConfig.ConditionPathExists = "${runnerHome}/runner.token";
    path = [
      pkgs.git
      "/run/current-system/sw"
    ];
    environment = {
      HOME = runnerHome;
      SWEEP_WAITING_DAYS = toString cfg.waiting.days;
      SWEEP_WAITING_COUNT = toString cfg.waiting.count;
    };
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
      # As root, since butler-notify's spool takes only its group and it asks systemd whether the
      # runner runs; from the runner's file it takes ids, times, counts and titles cleaned of markup.
      # Its first run seeds its state silently, so the deploy that brought this in sends nothing.
      ExecStartPost = "+${sweep "notify"}";
    };
  };

  config.systemd.tmpfiles.rules = [ "d /var/lib/backlogic-sweep-notify 0700 root root -" ];

  config.systemd.timers.backlogic-sweep = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "5min";
      OnUnitInactiveSec = "10min";
    };
  };
}
