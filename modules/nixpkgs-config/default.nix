{ pkgs, ... }:
let
  nixpkgs.config = {
    allowUnfree = true;

    # Allow for certain insecure packages
    permittedInsecurePackages = [ "electron-25.9.0" "nix-2.16.2" ];
  };

  nix = {
    package = pkgs.lix;

    settings = {
      # Enable Flakes
      experimental-features = [
        "nix-command"
        "flakes"
      ];

      # Allow root users access to the Nix store
      trusted-users = [
        "root"
        "@wheel"
      ];
      fallback = false;

      extra-substituters = [
        "https://nix-community.cachix.org"
      ];

      extra-trusted-public-keys = [
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      ];
    };
  };
in
{
  nixosSystemModule = { inherit nix nixpkgs; };
  darwinSystemModule = { inherit nix nixpkgs; };
}
