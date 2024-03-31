{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: {
  imports = [
    ./git.nix
    ./sway.nix
    ./rofi.nix
    ./waybar.nix
    ./zsh.nix
    ./theme.nix
    ./dunst.nix
  ];
}
