{
  imports = [
    ./boot.nix
    ./fonts.nix
    ./hardware.nix
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
  programs.zsh.enable = true;
  programs.gnupg.agent.enable = true;

  services.openssh.enable = true;
}
