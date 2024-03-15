{
  imports = [./gnupg.nix ./zsh.nix ./nixvim.nix];

  # Required to prevent Home Manager crashing
  # https://github.com/nix-community/home-manager/issues/3113
  programs.dconf.enable = true;

  programs.steam = {
    enable = true;
    localNetworkGameTransfers.openFirewall = true;
  };
}
