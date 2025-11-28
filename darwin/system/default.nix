{
  ids.gids.nixbld = 350;

  imports = [
    ./fonts.nix
  ];

  # Zsh config is done under shared/home, but must be explicitly enabled here also
  programs.zsh.enable = true;
}
