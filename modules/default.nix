{ lib, inputs, config, host, ... }:
let
  inherit (lib) mkOption types;
in
{
  imports = [
    ./home
    ./hyprland
    ./cyberdream
    ./cow
  ];

  options = {
    darwinModule = mkOption {
      type = types.attrsOf types.anything;
      default = { };
    };

    nixosModule = mkOption {
      type = types.attrsOf types.anything;
      default = { };
    };

    nixosHomeModule = mkOption {
      type = types.attrsOf types.anything;
      default = { };
    };

    darwinHomeModule = mkOption {
      type = types.attrsOf types.anything;
      default = { };
    };

    sharedSystemModule = mkOption {
      type = types.attrsOf types.anything;
      default = { };
    };

    sharedHomeModule = mkOption {
      type = types.attrsOf types.anything;
      default = { };
    };

    darwinConfigurations = mkOption {
      type = types.attrsOf types.anything;
      default = { };
    };

    nixosConfigurations = mkOption {
      type = types.attrsOf types.anything;
      default = { };
    };
  };

  config = {
    darwinConfigurations.${host.hostname} = inputs.nix-darwin.lib.darwinSystem {
      specialArgs = { inherit inputs; };
      inherit (host) system;

      modules = [
        inputs.home-manager.darwinModules.home-manager
        inputs.nixvim.nixDarwinModules.nixvim

        ../darwin/system
        ../shared/modules/nixvim

        config.darwinModule
        config.sharedSystemModule
      ];
    };

    nixosConfigurations.${host.hostname} = lib.nixosSystem {
      specialArgs = { inherit inputs; };
      inherit (host) system;

      modules = [
        inputs.home-manager.nixosModules.home-manager
        inputs.nixvim.nixosModules.nixvim

        ../nixos/system
        ../shared/modules/nixvim

        config.nixosModule
        config.sharedSystemModule
      ];
    };
  };
}
