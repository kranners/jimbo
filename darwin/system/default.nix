{
  security.pam.services.sudo_local.touchIdAuth = true;
  ids.gids.nixbld = 30000;

  imports = [
    ./users.nix
    ./fonts.nix
    ./autoraise.nix
  ];

  system.defaults = {
    finder = {
      AppleShowAllExtensions = true;
      FXPreferredViewStyle = "clmv";
    };

    screencapture.location = "~/Pictures";
  };

  # Zsh config is done under shared/home, but must be explicitly enabled here also
  programs.zsh.enable = true;

  # stateVersion didn't need to be defined until 6th November, 2024 flake update
  # Hardcoding to v5
  system.stateVersion = 5;
}
