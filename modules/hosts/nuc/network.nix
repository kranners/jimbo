{ config, lib, ... }:
let
  cfg = config.nuc.lan;
in
{
  # DHCP by default, which is what the installer and the first boot use; a static address once the NUC's
  # interface name is known, from `ip link` on it or its facter.json.
  options.nuc.lan = {
    interface = lib.mkOption {
      description = "The NUC's wired interface, such as eno1, for a static address.";
      type = lib.types.nullOr lib.types.str;
      default = null;
    };

    address = lib.mkOption {
      description = "A static LAN address with its prefix, such as 192.168.4.30/24, or null for DHCP.";
      type = lib.types.nullOr lib.types.str;
      default = null;
    };

    gateway = lib.mkOption {
      description = "The LAN's gateway, with a static address.";
      type = lib.types.nullOr lib.types.str;
      default = null;
    };
  };

  config = lib.mkIf (cfg.address != null) {
    assertions = [
      {
        assertion = cfg.interface != null && cfg.gateway != null;
        message = "nuc.lan.address needs nuc.lan.interface and nuc.lan.gateway too";
      }
    ];

    networking.interfaces = lib.optionalAttrs (cfg.interface != null) {
      ${cfg.interface} = {
        useDHCP = false;
        ipv4.addresses = [
          {
            address = lib.head (lib.splitString "/" cfg.address);
            prefixLength = lib.toInt (lib.last (lib.splitString "/" cfg.address));
          }
        ];
      };
    };
    networking.defaultGateway = cfg.gateway;
    networking.nameservers = [ cfg.gateway ];
  };
}
