{ pkgs, ... }:
let

in
{
  imports = [
    ./managers.nix
    ./android.nix
    ./secrets.nix
    ./scripts.nix
  ];

  home.packages = [
    pkgs.nixpkgs-fmt
    pkgs.discord
    pkgs.nurl
    pkgs.nix-output-monitor
  ];

  # This value determines the Home Manager release that your configuration is
  # compatible with. This helps avoid breakage when a new Home Manager release
  # introduces backwards incompatible changes.
  #
  # You should not change this value, even if you update Home Manager. If you do
  # want to update the value, then make sure to first check the Home Manager
  # release notes.
  home.stateVersion = "23.11"; # Please read the comment before changing.
}
