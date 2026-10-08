{ config, lib, ... }:
{
  services.prometheus.exporters.node.enable = true;

  networking.firewall.interfaces = lib.genAttrs [ "wlp1s0" "wg0" ] (_: {
    allowedTCPPorts = [ config.services.prometheus.exporters.node.port ];
  });
}
