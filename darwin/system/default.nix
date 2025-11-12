{
  ids.gids.nixbld = 350;

  imports = [
    ./users.nix
    ./fonts.nix
    ./autoraise.nix
  ];

  # Zsh config is done under shared/home, but must be explicitly enabled here also
  programs.zsh.enable = true;

  # stateVersion didn't need to be defined until 6th November, 2024 flake update
  # Hardcoding to v5
  # Hi Aaron updating to v6, new machine install. See you next time
  system.stateVersion = 6;
}
