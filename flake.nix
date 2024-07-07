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

    nh-darwin = {
      url = "github:ToyVo/nh";
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
  };

  outputs =
    { nixpkgs
    , home-manager
    , nixvim
    , nur
    , nix-darwin
    , ...
    } @ inputs: {
      darwinConfigurations =
        let
          system = "aarch64-darwin";
        in
        {
          cassandra = nix-darwin.lib.darwinSystem {
            specialArgs = { inherit inputs; };
            inherit system;

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

                  users.aaronpierce = {
                    imports = [ ./darwin/home ./shared/modules/home ];
                  };
                };
              }
            ];
          };
        };

      nixosConfigurations =
        let
          system = "x86_64-linux";
        in
        {
          jimbo = nixpkgs.lib.nixosSystem {
            specialArgs = { inherit inputs; };
            inherit system;

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
