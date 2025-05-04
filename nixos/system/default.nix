{
  imports = [
    ./boot.nix
    ./fonts.nix
    ./hardware.nix
    ./users.nix
    ./steam.nix
    ./graphics.nix
    ./sound.nix
    ./security.nix
    ./xdg.nix
    ./locale.nix
    ./nix-ld.nix
  ];

  # Enable networking
  networking = {
    networkmanager.enable = true;
    hostName = "jimbo";
  };

  # Required to prevent Home Manager crashing
  # https://github.com/nix-community/home-manager/issues/3113
  programs.dconf.enable = true;

  programs.gnupg.agent.enable = true;

  services.openssh.enable = true;

  services.flatpak = {
    enable = true;
    packages = [ "flathub:app/org.vinegarhq.Sober//stable" ];
    remotes = {
      "flathub" = "https://dl.flathub.org/repo/flathub.flatpakrepo";
    };
  };

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "23.11"; # Did you read the comment?
}
