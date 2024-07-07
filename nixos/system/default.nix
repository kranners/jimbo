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
    ./services.nix
    ./vial.nix
    ./nix-index.nix
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

  environment.systemPackages = with pkgs; [
    # Nix development tools
    nixfmt-rfc-style
    gnumake
    gnupg
    manix
    nurl
    eza
    btop
    htop

    # Basic vim is great as a git EDITOR, etc
    vim

    # Required libs for background services
    libnotify
    pipewire
  ];

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "23.11"; # Did you read the comment?
}
