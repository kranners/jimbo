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

  outputs =
    { nixpkgs
    , home-manager
    , nixvim
    , nix-darwin
    , ...
    } @ inputs: let
      inherit (nixpkgs) lib legacyPackages;

      # systems = ["aarch64-darwin" "x86_64-linux"];

      forEachSystem = system: lib.evalModules {
        specialArgs = {
          inherit inputs system;
          pkgs = legacyPackages.${system};
        };

        modules = [
          ./modules
          {
            cow = true;
            cyberdream-theme = "dark";
          }
        ];
      };

      moduleFlakeOutput = forEachSystem "aarch64-darwin";
    in moduleFlakeOutput.config;
}
