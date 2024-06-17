{
  services.nix-daemon.enable = true;
  nix.settings.experimental-features = "nix-command flakes";
  nixpkgs.config.allowUnfree = true;

  security.pam.enableSudoTouchIdAuth = true;

  imports = [
    ./homebrew.nix
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
}
