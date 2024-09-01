{ pkgs, ... }: {
  imports = [
    ./boot.nix
    ./fonts.nix
    ./hardware.nix
    ./home-manager.nix
    ./login.nix
    ./overlays.nix
    ./users.nix
    ./x11.nix
    ./gpg.nix
    ./steam.nix
    ./graphics.nix
    ./sound.nix
    ./security.nix
    ./xdg.nix
    ./locale.nix
    ./services.nix
    ./vial.nix
    ./nix-index.nix
    ./openrazer.nix
  ];

  # Enable Flakes
  nix.package = pkgs.nixFlakes;
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Allow root users access to the Nix store
  nix.settings.trusted-users = [ "root" "@wheel" ];

  # Allow unfree packages
  nixpkgs.config = {
    allowUnfree = true;

    # Allow for certain insecure packages
    permittedInsecurePackages = [ "electron-25.9.0" "nix-2.16.2" ];
  };

  # Enable networking
  networking = {
    networkmanager.enable = true;
    hostName = "jimbo";
  };
}
