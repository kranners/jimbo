{
  services.nix-daemon.enable = true;

  security.pam.enableSudoTouchIdAuth = true;

  imports = [
    ./users.nix
    ./fonts.nix
    ./autoraise.nix
  ];

  # Zsh config is done under darwin/home, but must be explicitly enabled here also
  programs.zsh.enable = true;

  system.defaults = {
    finder = {
      AppleShowAllExtensions = true;
      FXPreferredViewStyle = "clmv";
    };

    screencapture.location = "~/Pictures";
  };

  # Reloads system preferences post nix-darwin activation
  # Stolen from: https://medium.com/@zmre/nix-darwin-quick-tip-activate-your-preferences-f69942a93236
  system.activationScripts.postUserActivation.text = ''
    /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u
  '';

  # stateVersion didn't need to be defined until 6th November, 2024 flake update
  # Hardcoding to v5
  system.stateVersion = 5;
}
