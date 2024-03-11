{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: {
  imports = [./git.nix ./neovim.nix ./rofi.nix ./waybar.nix];
}
