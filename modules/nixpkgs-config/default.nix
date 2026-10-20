{ lib, ... }:
let
  nixpkgs.config = {
    allowUnfree = true;
  };

  nix = {
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

    gc = {
      automatic = true;
      options = "--delete-older-than 7d";
    };
  };
in
{
  nixosSystemModule = {
    inherit nixpkgs;
    nix = lib.recursiveUpdate nix { gc.dates = "weekly"; };
  };
  darwinSystemModule = { inherit nix nixpkgs; };
}
