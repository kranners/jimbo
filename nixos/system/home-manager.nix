{ pkgs, ... }: {
  environment.systemPackages = [ pkgs.home-manager ];

  # Required to prevent Home Manager crashing
  # https://github.com/nix-community/home-manager/issues/3113
  programs.dconf.enable = true;
}
