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
    config.darwinHomeModule
    config.sharedHomeModule
  ];

  nixosSystemModule = mkHome [
    config.nixosHomeModule
    config.sharedHomeModule
  ];

  nixosHomeModule = {
    # Give Home Manager the power to stop and start systemd services
    systemd.user.startServices = "sd-switch";
  };

  sharedHomeModule = {
    imports = [
      ./scripts.nix
      ./zoxide.nix
      ./krabby.nix
      ./uv
    ];

    programs.direnv = {
      enable = true;
      enableZshIntegration = true;
    };

    # Let Home Manager install and manage itself.
    programs.home-manager.enable = true;
  };
}
