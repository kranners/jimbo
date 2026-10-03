{
  config,
  lib,
  pkgs,
  ...
}:
let
  port = 5433;
  lanInterfaces = [
    "wlp2s0"
    "wg0"
  ];
in
{
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_18;
    enableTCPIP = true;
    settings.port = port;
    authentication = ''
      host all bowerbird 192.168.4.0/22 scram-sha-256
      host all bowerbird 10.100.0.0/24 scram-sha-256
    '';
    initialScript = pkgs.writeText "bowerbird-environments.sql" ''
      create role bowerbird superuser login password 'bowerbird';
    '';
  };

  networking.firewall.interfaces = lib.genAttrs lanInterfaces (_: {
    allowedTCPPorts = [ port ];
  });

  systemd.services.bowerbird-template = {
    description = "Bowerbird branch template, cloned from production";
    requires = [ "postgresql.service" ];
    after = [
      "postgresql.service"
      "bowerbird-backup.service"
    ];
    path = [ config.services.postgresql.package ];
    unitConfig.ConditionPathExists = "/srv/bowerbird/bin/template";
    serviceConfig = {
      Type = "oneshot";
      User = "bowerbird";
      ExecStart = "/srv/bowerbird/bin/template";
    };
  };

  systemd.timers.bowerbird-template = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "03:30";
      Persistent = true;
    };
  };
}
