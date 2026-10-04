{ lib, pkgs, ... }:
let
  checkout = "/srv/workaholic";
  home = "/var/lib/workaholic";
  profile = "mixed";
  runners = [
    1
    2
    3
  ];
in
{
  users.users.workaholic = {
    isSystemUser = true;
    group = "workaholic";
    inherit home;
    linger = true;
  };
  users.groups.workaholic = { };

  systemd.tmpfiles.rules = [
    "d ${checkout} 0755 aaron users -"
    "d ${home} 0750 workaholic workaholic -"
    "d ${home}/.config 0755 workaholic workaholic -"
  ];

  systemd.services."workaholic@" = {
    description = "workaholic runner %i, works GitHub issues within spare compute and Claude Max usage";
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    unitConfig.ConditionPathExists = "${checkout}/package.json";
    environment = {
      SHELL = "${pkgs.bashInteractive}/bin/bash";
      TEST_CHROMIUM_PATH = "${pkgs.google-chrome}/bin/google-chrome-stable";
    };
    path = [
      pkgs.git
      pkgs.claude-code
      pkgs.nodejs_24
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
