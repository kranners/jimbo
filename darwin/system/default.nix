{ ... }: {
  services.nix-daemon.enable = true;
  nix.settings.experimental-features = "nix-command flakes";

  security.pam.enableSudoTouchIdAuth = true;

  imports = [
    ./homebrew.nix
    ./users.nix
    ./zsh.nix
  ];
}
