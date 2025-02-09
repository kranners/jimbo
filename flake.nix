{
  description = "flake for jimbo";

  inputs = {
    nixpkgs = {
      url = "github:nixos/nixpkgs/nixpkgs-unstable";
    };

    firefox-addons = {
      url = "gitlab:rycee/nur-expressions?dir=pkgs/firefox-addons";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    awesome-neovim-plugins = {
      url = "github:m15a/flake-awesome-neovim-plugins";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixvim = {
      url = "github:nix-community/nixvim";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-darwin = {
      url = "github:LnL7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    walker = {
      url = "github:abenz1267/walker";
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

    alacritty-themes = {
      url = "github:Johnsoct/alacritty";
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

    tiny-inline-diagnostic = {
      url = "github:rachartier/tiny-inline-diagnostic.nvim";
      flake = false;
    };

    swww = {
      url = "github:LGFae/swww";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    rofi-themes-collection = {
      url = "github:newmanls/rofi-themes-collection";
      flake = false;
    };
  };

  outputs = { nixpkgs, ... } @ inputs: {
    darwinConfigurations = {
      cassandra = inputs.nix-darwin.lib.darwinSystem {
        specialArgs = { inherit inputs; };
        system = "aarch64-darwin";

        modules = [
          inputs.home-manager.darwinModules.home-manager
          inputs.nixvim.nixDarwinModules.nixvim

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
          inputs.home-manager.nixosModules.home-manager
          inputs.nixvim.nixosModules.nixvim

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
