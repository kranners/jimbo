{pkgs, ...}: {
  imports = [./git.nix ./neovim.nix ./rofi.nix];
}
