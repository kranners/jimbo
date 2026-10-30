{
  config,
  lib,
  pkgs,
  host,
  ...
}:
let
  panelRemotePort = 8124;
in
{
  systemd.services.panel-remote = {
    description = "Panel brightness over HTTP for Home Assistant on spike";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      User = host.username;
      # `brightness` locks a file in /tmp, which root's schedule services may already own.
      PrivateTmp = true;
      ExecStart = "${lib.getExe pkgs.python3} ${./panel-remote.py} ${lib.getExe config.kiosk.panelCommand} ${toString panelRemotePort}";
      Restart = "always";
      RestartSec = 5;
    };
  };

  networking.firewall.interfaces.wg0.allowedTCPPorts = [ panelRemotePort ];
}
