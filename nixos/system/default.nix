{ config
, pkgs
, inputs
, ...
}: {
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
    ./gpg.nix
    ./steam.nix
    ./opengl.nix
    ./sound.nix
    ./security.nix
    ./xdg.nix
    ./locale.nix
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

  environment.systemPackages = [
    # Nix development tools
    pkgs.nixfmt-rfc-style
    pkgs.alejandra
    pkgs.gnumake
    pkgs.gnupg
    pkgs.manix

    # It's just really neat
    pkgs.eza

    # Required by waybar and dunst
    pkgs.libnotify

    # Required for screensharing
    pkgs.pipewire
  ];

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "23.11"; # Did you read the comment?
}
