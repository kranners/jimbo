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
    ./neovim
    ./font-size
    ./launcher
    ./file-manager
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

          ../nixos/system
          config.nixosSystemModule
          config.sharedSystemModule
        ];
      };
    };
  };
}
