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
    config.darwinHomeModule
    config.sharedHomeModule
  ];

  nixosSystemModule = mkHome [
    ../../nixos/home
    config.nixosHomeModule
    config.sharedHomeModule
  ];

  sharedHomeModule = {
    imports = [
      ./git.nix
      ./scripts.nix
      ./zoxide.nix
      ./alacritty.nix
      ./krabby.nix
      ./uv
    ];

    programs.direnv = {
      enable = true;
      enableZshIntegration = true;
    };
  };
}
