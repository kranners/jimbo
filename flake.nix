{
  description = "flake for jimbo";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    nur.url = "github:nix-community/NUR";

    firefox-addons.url = "gitlab:rycee/nur-expressions?dir=pkgs/firefox-addons";
    awesome-neovim-plugins.url = "github:m15a/flake-awesome-neovim-plugins";
    nixvim.url = "github:nix-community/nixvim";
    nix-vscode-extensions.url = "github:nix-community/nix-vscode-extensions";

    nix-darwin = {
      url = "github:LnL7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    toggleterm-manager = {
      url = "github:ryanmsnyder/toggleterm-manager.nvim";
      flake = false;
    };

    resession = {
      url = "github:stevearc/resession.nvim";
      flake = false;
    };

    telescope-resession = {
      url = "github:scottmckendry/telescope-resession.nvim";
      flake = false;
    };

    cyberdream = {
      url = "github:scottmckendry/cyberdream.nvim";
      flake = false;
    };

    windline = {
      url = "github:windwp/windline.nvim";
      flake = false;
    };

    flatten = {
      url = "github:willothy/flatten.nvim";
      flake = false;
    };

    grug-far = {
      url = "github:MagicDuck/grug-far.nvim";
      flake = false;
    };

    catppuccin-zellij = {
      url = "github:catppuccin/zellij";
      flake = false;
    };
  };

  outputs =
    { nixpkgs
    , home-manager
    , nixvim
    , nur
    , nix-darwin
    , ...
    } @ inputs: {
      darwinConfigurations = {
        cassandra = nix-darwin.lib.darwinSystem {
          specialArgs = { inherit inputs; };
          system = "aarch64-darwin";

          modules = [
            home-manager.darwinModules.home-manager
            nixvim.nixDarwinModules.nixvim

            ./darwin/system
            ./shared/modules/nixvim

            {
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                extraSpecialArgs = { inherit inputs; };

                backupFileExtension = "backup";

                users.aaronpierce = {
                  imports = [ ./darwin/home ./shared/modules/home ];
                };
              };
            }
          ];
        };
      };

      nixosConfigurations = {
        jimbo = nixpkgs.lib.nixosSystem {
          specialArgs = { inherit inputs; };
          system = "x86_64-linux";

          modules = [
            home-manager.nixosModules.home-manager
            nixvim.nixosModules.nixvim
            nur.nixosModules.nur

            ./nixos/system
            ./shared/modules/nixvim

            {
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                extraSpecialArgs = { inherit inputs; };

                backupFileExtension = "backup";

                users.aaron = {
                  imports = [ ./nixos/home ./shared/modules/home ];
                };
              };
            }
          ];
        };
      };
    };
}
