{
  services.nix-daemon.enable = true;
  nix.settings.experimental-features = "nix-command flakes";
  nixpkgs.config.allowUnfree = true;

  imports = [
    ./users.nix
    ./fonts.nix
    ./autoraise.nix
    ./managers.nix
    ./secrets.nix
    ./zsh.nix
    ./programs.nix
    ./preferences.nix
  ];

  # Reloads system preferences post nix-darwin activation
  # See: https://medium.com/@zmre/nix-darwin-quick-tip-activate-your-preferences-f69942a93236
  system.activationScripts.postUserActivation.text = ''
    /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u
  '';

  # This value determines the Home Manager release that your configuration is
  # compatible with. This helps avoid breakage when a new Home Manager release
  # introduces backwards incompatible changes.
  #
  # You should not change this value, even if you update Home Manager. If you do
  # want to update the value, then make sure to first check the Home Manager
  # release notes.
  home.home.stateVersion = "23.11";
}
