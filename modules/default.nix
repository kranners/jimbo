{ lib, inputs, config, host, ... }:
let
  inherit (lib) mkOption mkIf types;
  inherit (host) system;

  platform = lib.lists.last (lib.strings.splitString "-" system);
in
{
  imports = [
    ./home
    ./hyprland
    ./cyberdream
    ./apps
    ./nixpkgs-config
    ./completion
    ./nixvim
    ./font-size
  ];

  options = {
    darwinSystemModule = mkOption {
      type = types.deferredModule;
      default = { };
    };

    nixosSystemModule = mkOption {
      type = types.deferredModule;
      default = { };
    };

    nixosHomeModule = mkOption {
      type = types.deferredModule;
      default = { };
    };

    darwinHomeModule = mkOption {
      type = types.deferredModule;
      default = { };
    };

    sharedSystemModule = mkOption {
      type = types.deferredModule;
      default = { };
    };

    sharedHomeModule = mkOption {
      type = types.deferredModule;
      default = { };
    };

    darwinConfigurations = mkOption {
      type = types.raw;
      default = { };
    };

    nixosConfigurations = mkOption {
      type = types.raw;
      default = { };
    };
  };

  config = {
    darwinConfigurations = mkIf (platform == "darwin") {
      ${host.hostname} = inputs.nix-darwin.lib.darwinSystem {
        specialArgs = { inherit inputs host; };
        inherit (host) system;

        modules = [
          inputs.home-manager.darwinModules.home-manager
          inputs.nixvim.nixDarwinModules.nixvim

          ../darwin/system
          config.darwinSystemModule
          config.sharedSystemModule
        ];
      };
    };

    nixosConfigurations = mkIf (platform == "linux") {
      ${host.hostname} = inputs.nixpkgs.lib.nixosSystem {
        specialArgs = { inherit inputs host; };
        inherit (host) system;

        modules = [
          inputs.home-manager.nixosModules.home-manager
          inputs.nixvim.nixosModules.nixvim

          ../nixos/system
          config.nixosSystemModule
          config.sharedSystemModule
        ];
      };
    };
  };
}
