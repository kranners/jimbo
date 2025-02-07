{ lib, inputs, config, ... }: let
  inherit (lib) mkOption types;
in {
  imports = [
    ./hyprland
    ./cyberdream
    ./cow
  ];

  options = {
    darwinModule = mkOption {
      type = types.attrsOf types.anything;
      default = {};
    };

    nixosModule = mkOption {
      type = types.attrsOf types.anything;
      default = {};
    };

    nixosHomeModule = mkOption {
      type = types.attrsOf types.anything;
      default = {};
    };

    darwinHomeModule = mkOption {
      type = types.attrsOf types.anything;
      default = {};
    };

    sharedSystemModule = mkOption {
      type = types.attrsOf types.anything;
      default = {};
    };

    sharedHomeModule = mkOption {
      type = types.attrsOf types.anything;
      default = {};
    };

    darwinConfigurations = mkOption {
      type = types.attrsOf types.anything;
      default = {};
    };

    nixosConfigurations = mkOption {
      type = types.attrsOf types.anything;
      default = {};
    };
  };

  config = {
    darwinConfigurations = {
      cassandra = inputs.nix-darwin.lib.darwinSystem {
        specialArgs = { inherit inputs; };
        system = "aarch64-darwin";

        modules = [
          inputs.home-manager.darwinModules.home-manager
          inputs.nixvim.nixDarwinModules.nixvim

          ../darwin/system
          ../shared/modules/nixvim

          config.darwinModule
          config.sharedSystemModule

          {
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              extraSpecialArgs = { inherit inputs; };

              backupFileExtension = "backup";

              users.aaronpierce = {
                imports = [
                  ../darwin/home
                  ../shared/modules/home
                  config.darwinHomeModule
                  config.sharedHomeModule
                ];
              };
            };
          }
        ];
      };
    };

    nixosConfigurations = {
      jimbo = lib.nixosSystem {
        specialArgs = { inherit inputs; };
        system = "x86_64-linux";

        modules = [
          inputs.home-manager.nixosModules.home-manager
          inputs.nixvim.nixosModules.nixvim

          ../nixos/system
          ../shared/modules/nixvim

          config.nixosModule
          config.sharedSystemModule

          {
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              extraSpecialArgs = { inherit inputs; };

              backupFileExtension = "backup";

              users.aaron = {
                imports = [
                  ../nixos/home
                  ../shared/modules/home
                  config.nixosHomeModule
                  config.sharedHomeModule
                ];
              };
            };
          }
        ];
      };
    };
  };
}
