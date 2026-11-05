{ config, lib, ... }:
let
  names = import ../../spike-dns/names.nix;

  # Caddy's sites under cute.engineer, each served on 10.100.0.1, which names.nix must list for the Macs.
  caddySites = lib.filter (
    site: lib.hasSuffix ".cute.engineer" site && site != "spike.cute.engineer"
  ) (lib.attrNames config.services.caddy.virtualHosts);
in
{
  services.cloudflare-dyndns = {
    enable = true;
    apiTokenFile = "/var/lib/secrets/cloudflare-dyndns-token";
    domains = [ "spike.cute.engineer" ];
  };

  assertions = [
    {
      assertion = lib.all (site: lib.elem site names) caddySites;
      message = "modules/spike-dns/names.nix is missing Caddy sites: ${toString (lib.subtractLists names caddySites)}";
    }
  ];

  # A resolver for WireGuard peers alone, so a peer on a foreign network still finds spike's names, which public DNS
  # does not serve and the home network's DNS hides: it answers each of them with 10.100.0.1 and forwards everything
  # else to the upstream servers in spike's own resolv.conf, which it leaves alone.
  services.dnsmasq = {
    enable = true;
    resolveLocalQueries = false;
    settings = {
      interface = "wg0";
      except-interface = "lo";
      # Binds wg0's address whenever it appears, so dnsmasq starting before the tunnel still serves it.
      bind-dynamic = true;
      no-hosts = true;
      domain-needed = true;
      bogus-priv = true;
      host-record = map (name: "${name},10.100.0.1") names;
    };
  };

  networking.firewall.interfaces.wg0 = {
    allowedUDPPorts = [ 53 ];
    allowedTCPPorts = [ 53 ];
  };
}
