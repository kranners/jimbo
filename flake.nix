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

    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
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
  };

  outputs = { nixpkgs, ... } @ inputs:
    let
      inherit (nixpkgs) lib;

      hosts = [
        {
          system = "x86_64-linux";
          hostname = "jimbo";
          username = "aaron";
        }

        {
          system = "aarch64-darwin";
          hostname = "cassandra";
          username = "aaronpierce";
        }
      ];

      flakeOutputPerHost = host: lib.evalModules {
        specialArgs = {
          inherit inputs host;

          pkgs = import nixpkgs {
            system = host.system;

            config = {
              allowUnfree = true;
            };
          };
        };

        modules = [
          ./modules
          {
            cyberdream-theme = "dark";

            # TODO: epwalsh/obsidian.nvim doesn't support blink-cmp yet.
            # TODO: need to move to regular Lua config, then install obsidian-nvim/obsidian.nvim
            completion-engine = "cmp";
          }
        ];
      };

      flakeOutputs = lib.forEach hosts flakeOutputPerHost;

      # [attrsets] -> attrset
      mergedOutput = lib.foldl' lib.recursiveUpdate { } flakeOutputs;
    in
    mergedOutput.config;
}
