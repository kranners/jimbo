{ config, pkgs, inputs, ... }: {
  imports = [
    ./boot.nix
    ./environment.nix
    ./fonts.nix
    ./hardware.nix
    ./home-manager.nix
    ./login.nix
    ./overlays.nix
    ./users.nix
    ./x11.nix
  ];
}
