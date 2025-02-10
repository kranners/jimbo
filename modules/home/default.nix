{ config, host, inputs, ... }:
let
  mkHome = imports: {
    home-manager = {
      useGlobalPkgs = true;
      useUserPackages = true;
      extraSpecialArgs = { inherit inputs host; };
      backupFileExtension = "backup";

      users.${host.username} = { inherit imports; };
    };
  };
in
{
  darwinSystemModule = mkHome [
    ../../darwin/home
    ../../shared/modules/home
    config.darwinHomeModule
    config.sharedHomeModule
  ];

  nixosSystemModule = mkHome [
    ../../nixos/home
    ../../shared/modules/home
    config.nixosHomeModule
    config.sharedHomeModule
  ];
}
