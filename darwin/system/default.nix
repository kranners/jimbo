{
  ids.gids.nixbld = 350;

  imports = [
    ./users.nix
    ./fonts.nix
    ./autoraise.nix
  ];

  # Zsh config is done under shared/home, but must be explicitly enabled here also
  programs.zsh.enable = true;
}
