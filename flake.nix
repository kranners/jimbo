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

    stylix = {
      url = "github:danth/stylix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { nixpkgs
    , home-manager
    , nixvim
    , nur
    , nix-darwin
    , stylix
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
              # stylix.darwinModules.stylix

              ./darwin/system
              ./shared/modules/nixvim

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
              nixvim.nixosModules.nixvim
              nur.nixosModules.nur

              ./nixos/system
              ./shared/modules/nixvim

              {
                home-manager = {
                  useGlobalPkgs = true;
                  useUserPackages = true;
                  extraSpecialArgs = { inherit inputs; };
                  sharedModules = [ stylix.homeManagerModules.stylix ];
                  users.aaron = import ./nixos/home;
                };
              }
            ];
          };
        };
    };
}
