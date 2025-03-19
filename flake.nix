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

    nix-darwin = {
      url = "github:LnL7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    alacritty-themes = {
      url = "github:Johnsoct/alacritty";
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
          { cyberdream-theme = "dark"; }
        ];
      };

      flakeOutputs = lib.forEach hosts flakeOutputPerHost;

      # [attrsets] -> attrset
      mergedOutput = lib.foldl' lib.recursiveUpdate { } flakeOutputs;
    in
    mergedOutput.config;
}
