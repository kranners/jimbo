{ pkgs, ... }:
let
  credential = "tunnel-token";
  apiPort = 4201;
in
{
  # Cloud sessions run by backlogic's runner reach the instance's API through this tunnel
  # (backlogic's docs/decisions/cloud-sessions.md); every request still needs a session token.
  services.caddy.virtualHosts."http://:${toString apiPort}".extraConfig = ''
    bind 127.0.0.1
    handle /api/* {
      reverse_proxy 127.0.0.1:4200
    }
    respond 404
  '';

  systemd.services.backlogic-tunnel = {
    description = "Cloudflare Tunnel carrying backlogic's API to cloud sessions";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [
      "network-online.target"
      "caddy.service"
    ];
    unitConfig.ConditionPathExists = "/var/lib/secrets/cloudflared-backlogic-token";
    serviceConfig = {
      DynamicUser = true;
      LoadCredential = [ "${credential}:/var/lib/secrets/cloudflared-backlogic-token" ];
      ExecStart = "${pkgs.cloudflared}/bin/cloudflared tunnel --no-autoupdate run --token-file %d/${credential}";
      Restart = "always";
      RestartSec = 10;
    };
  };
}
