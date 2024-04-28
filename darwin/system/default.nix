{ ... }: {
  services.nix-daemon.enable = true;
  nix.settings.experimental-features = "nix-command flakes";

  imports = [
    ./homebrew.nix
    ./users.nix
    ./zsh.nix
  ];
}
