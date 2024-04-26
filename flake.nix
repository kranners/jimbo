{
  description = "flake for jimbo";
  # hi

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager";
    nixvim.url = "github:nix-community/nixvim";
    nix-vscode-extensions.url = "github:nix-community/nix-vscode-extensions";
    nur.url = "github:nix-community/NUR";
    firefox-addons.url = "gitlab:rycee/nur-expressions?dir=pkgs/firefox-addons";

    # https://github.com/m15a/flake-awesome-neovim-plugins
    awesome-neovim-plugins.url = "github:m15a/flake-awesome-neovim-plugins";
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
    , ...
    }@inputs:
    let
      system = "x86_64-linux";

      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      nixosConfigurations = {
        jimbo = nixpkgs.lib.nixosSystem {
          specialArgs = { inherit inputs; };

          modules = [
            home-manager.nixosModules.default
            nur.nixosModules.nur

            ./nixos

            {
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                extraSpecialArgs = { inherit inputs; };
                users.aaron = import ./home;
              };
            }
          ];
        };
      };
    };
}
