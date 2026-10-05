{ pkgs, ... }:
let
  cloudflareToken = "cloudflare-token";
in
{
  services.caddy = {
    enable = true;
    package = pkgs.caddy.withPlugins {
      plugins = [ "github.com/caddy-dns/cloudflare@v0.2.4" ];
      hash = "sha256-dQvk6ezY6TQ1J7PjhCXnThF/SqVgPwBO8/RXzHCY+js=";
    };
    globalConfig = ''
      acme_dns cloudflare {file./run/credentials/caddy.service/${cloudflareToken}}
    '';
  };

  systemd.services.caddy.serviceConfig.LoadCredential = [
    "${cloudflareToken}:/var/lib/secrets/cloudflare-dyndns-token"
  ];

  networking.firewall.interfaces.wg0.allowedTCPPorts = [ 443 ];
}
