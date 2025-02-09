{ lib, inputs, ... }:
let
  inherit (lib) mkOption types;
in
{
  options = {
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
    darwinConfigurations = {
      cassandra = inputs.nix-darwin.lib.darwinSystem {
        specialArgs = { inherit inputs; };
        system = "aarch64-darwin";

        modules = [
          inputs.home-manager.darwinModules.home-manager
          inputs.nixvim.nixDarwinModules.nixvim

          ../darwin/system
          ../shared/modules/nixvim

          {
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              extraSpecialArgs = { inherit inputs; };

              backupFileExtension = "backup";

              users.aaronpierce = {
                imports = [ ../darwin/home ../shared/modules/home ];
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

          {
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              extraSpecialArgs = { inherit inputs; };

              backupFileExtension = "backup";

              users.aaron = {
                imports = [ ../nixos/home ../shared/modules/home ];
              };
            };
          }
        ];
      };
    };
  };
}
