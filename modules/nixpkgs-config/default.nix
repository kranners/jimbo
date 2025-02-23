{ pkgs, ... }:
let
  nixpkgs.config = {
    allowUnfree = true;
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
        "https://kranners.cachix.org"
      ];

      extra-trusted-public-keys = [
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "kranners.cachix.org-1:ZuxIgFNLP2qrpRXPKGMV1U+GErsAFU4Em4sqoOkJ0no="
      ];
    };
  };
in
{
  nixosSystemModule = { inherit nix nixpkgs; };
  darwinSystemModule = { inherit nix nixpkgs; };
}
