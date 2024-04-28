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
  };

  outputs =
    { self
    , nixpkgs
    , home-manager
    , nixvim
    , nix-vscode-extensions
    , nur
    , firefox-addons
    , awesome-neovim-plugins
    , nix-darwin
    , ...
    }@inputs: {

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

              ./darwin/system

              {
                home-manager = {
                  useGlobalPkgs = true;
                  useUserPackages = true;
                  extraSpecialArgs = { inherit inputs; };
                  users.aaronpierce = import ./darwin/home;
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
              home-manager.nixosModules.default
              nur.nixosModules.nur

              ./nixos/system

              {
                home-manager = {
                  useGlobalPkgs = true;
                  useUserPackages = true;
                  extraSpecialArgs = { inherit inputs; };
                  users.aaron = import ./nixos/home;
                };
              }
            ];
          };
        };
    };
}
