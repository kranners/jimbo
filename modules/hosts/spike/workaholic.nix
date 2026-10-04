{ pkgs, ... }:
let
  checkout = "/srv/workaholic";
  home = "/var/lib/workaholic";
  profile = "mixed";
in
{
  users.users.workaholic = {
    isSystemUser = true;
    group = "workaholic";
    inherit home;
  };
  users.groups.workaholic = { };

  systemd.tmpfiles.rules = [
    "d ${checkout} 0755 aaron users -"
    "d ${home} 0750 workaholic workaholic -"
  ];

  systemd.services.workaholic = {
    description = "workaholic, works GitHub issues within spare compute and Claude Max usage";
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    unitConfig.ConditionPathExists = "${checkout}/package.json";
    environment.SHELL = "${pkgs.bashInteractive}/bin/bash";
    path = [
      pkgs.git
      pkgs.claude-code
    ];

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

  systemd.timers.workaholic = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "5min";
      OnUnitInactiveSec = "15min";
    };
  };
}
