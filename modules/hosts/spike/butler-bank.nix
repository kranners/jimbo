{ config, pkgs, ... }:
let
  inherit (config.users.users.butler) home;

  token = "/var/lib/secrets/butler-up-token";

  python = name: pkgs.writers.writePython3Bin name { flakeIgnore = [ "E501" ]; };

  bank = python "bank" (builtins.readFile ./butler-bank/bank.py);
  butler-bank-sync = python "butler-bank-sync" (builtins.readFile ./butler-bank/sync.py);
in
{
  butler.commands.bank = {
    package = bank;
    description = ''
      Query Aaron's Up bank accounts and every transaction since 2021 with read-only SQLite SQL, from a copy refreshed nightly. Prints CSV, at most 200 rows.
      bank schema | bank sql <select statement>
    '';
    rules =
      map
        (verb: {
          match = [
            verb
            "**"
          ];
          lanes = [
            "interactive"
            "cron"
          ];
        })
        [
          "schema"
          "sql"
        ];
    skill = ./butler-skills/bank;
  };

  systemd.tmpfiles.rules = [ "d ${home}/bank 0700 butler butler -" ];

  systemd.services.butler-bank-sync = {
    description = "Copy Aaron's Up accounts and transactions into butler's bank database";
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    unitConfig.ConditionPathExists = token;
    serviceConfig = {
      Type = "oneshot";
      User = "butler";
      LoadCredential = "up-token:${token}";
      ExecStart = "${butler-bank-sync}/bin/butler-bank-sync";
    };
  };

  systemd.timers.butler-bank-sync = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "04:00";
      Persistent = true;
    };
  };
}
