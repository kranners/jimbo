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
    ./cow
  ];

  options = {
    darwinSystemModule = mkOption {
      type = types.attrsOf types.anything;
      default = { };
    };

    nixosSystemModule = mkOption {
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
          inputs.home-manager.darwinSystemModules.home-manager
          inputs.nixvim.nixDarwinModules.nixvim

          ../darwin/system
          ../shared/modules/nixvim

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
          inputs.home-manager.nixosSystemModules.home-manager
          inputs.nixvim.nixosSystemModules.nixvim

          ../nixos/system
          ../shared/modules/nixvim

          config.nixosSystemModule
          config.sharedSystemModule
        ];
      };
    };
  };
}
