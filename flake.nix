{
  description = "flake for jimbo";

  inputs = {
    nixpkgs = {
      url = "github:nixos/nixpkgs/nixpkgs-unstable";
    };

    nix-darwin = {
      url = "github:LnL7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { nixpkgs, ... }@inputs:
    let
      inherit (nixpkgs) lib;

      hosts = [
        {
          system = "x86_64-linux";
          hostname = "jimbo";
          username = "aaron";
          desktop = true;
          kiosk = false;
        }

        {
          system = "aarch64-darwin";
          hostname = "piggys-MBP";
          username = "aaron";
          desktop = true;
          kiosk = false;
        }

        {
          system = "x86_64-linux";
          hostname = "spike";
          username = "aaron";
          desktop = false;
          kiosk = false;
        }

        {
          system = "x86_64-linux";
          hostname = "framer";
          username = "aaron";
          desktop = false;
          kiosk = true;
        }
      ];

      flakeOutputPerHost =
        host:
        lib.evalModules {
          specialArgs = {
            inherit inputs host;

            pkgs = import nixpkgs {
              inherit (host) system;

              config = {
                allowUnfree = true;
              };
            };
          };

          modules = [
            ./modules
          ];
        };

      flakeOutputs = lib.forEach hosts flakeOutputPerHost;

      # [attrsets] -> attrset
      mergedOutput = lib.foldl' lib.recursiveUpdate { } flakeOutputs;
    in
    mergedOutput.config;
}
