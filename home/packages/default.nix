{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: {
  imports = [./git.nix ./hyprland.nix ./rofi.nix ./waybar.nix ./zsh.nix ./theme.nix];
}
