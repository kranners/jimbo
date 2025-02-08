{ config, host, inputs, ... }:
let
  mkHome = imports: {
    home-manager = {
      useGlobalPkgs = true;
      useUserPackages = true;
      extraSpecialArgs = { inherit inputs; };
      backupFileExtension = "backup";

      users.${host.username} = { inherit imports; };
    };
  };
in
{
  darwinModule = mkHome [
    ../../darwin/home
    ../../shared/modules/home
    config.darwinHomeModule
    config.sharedHomeModule
  ];

  nixosModule = mkHome [
    ../../nixos/home
    ../../shared/modules/home
    config.nixosHomeModule
    config.sharedHomeModule
  ];
}
