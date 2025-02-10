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
          ../shared/modules/nixvim

          config.darwinModule
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
          ../shared/modules/nixvim

          config.nixosModule
          config.sharedSystemModule
        ];
      };
    };
  };
}
