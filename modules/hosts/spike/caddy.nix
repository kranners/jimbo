{ config, pkgs, ... }:
let
  credential = "cloudflare-token";
in
{
  services.caddy = {
    enable = true;
    package = pkgs.caddy.withPlugins {
      plugins = [ "github.com/caddy-dns/cloudflare@v0.2.4" ];
      hash = "sha256-dQvk6ezY6TQ1J7PjhCXnThF/SqVgPwBO8/RXzHCY+js=";
    };
    globalConfig = ''
      acme_dns cloudflare {file./run/credentials/caddy.service/${credential}}
    '';
  };

  systemd.services.caddy.serviceConfig.LoadCredential = [
    "${credential}:${config.services.cloudflare-dyndns.apiTokenFile}"
  ];

  networking.firewall.interfaces.wg0.allowedTCPPorts = [ 443 ];
}
