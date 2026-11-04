{ config, lib, ... }:
let
  cfg = config.nuc.builder;
in
{
  options.nuc.builder = {
    enable = lib.mkEnableOption ''
      serving Nix builds to spike over WireGuard as the user nix-builder, whose key may only run nix-daemon --stdio,
      as spike does for framer; spike's half is nucBuilder in modules/hosts/spike/remote-builder.nix
    '';

    clientKeys = lib.mkOption {
      description = "Public keys allowed to build here, spike's root key /var/lib/secrets/nuc-builder-key.pub once made by hand there.";
      type = lib.types.listOf lib.types.str;
      default = [ ];
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.nix-builder = {
      isSystemUser = true;
      group = "nix-builder";
      useDefaultShell = true;
      openssh.authorizedKeys.keys = map (
        key: ''command="${config.nix.package}/bin/nix-daemon --stdio",restrict,from="10.100.0.1" ${key}''
      ) cfg.clientKeys;
    };
    users.groups.nix-builder = { };

    nix.settings.trusted-users = [ "nix-builder" ];
  };
}
