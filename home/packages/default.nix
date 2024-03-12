{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: {
  imports = [./git.nix ./hyprland.nix ./neovim.nix ./rofi.nix ./waybar.nix ./zsh.nix];
}
