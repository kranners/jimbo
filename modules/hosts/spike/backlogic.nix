{ lib, ... }:
let
  lanInterfaces = [
    "wlp2s0"
    "wg0"
  ];
in
{
  services.caddy.virtualHosts."backlogic.spike.cute.engineer".extraConfig = ''
    reverse_proxy 127.0.0.1:4200
  '';

  networking.firewall.interfaces = lib.genAttrs lanInterfaces (_: {
    allowedTCPPorts = [
      4200
      4201
    ];
  });
}
