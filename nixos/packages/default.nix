{
  config,
  pkgs,
  inputs,
  ...
}: {
  imports = [
    ./gnupg.nix
    ./zsh.nix
    ./nixvim.nix
    ./steam.nix
  ];

  environment.systemPackages = [
    # Nix development tools
    pkgs.alejandra
    pkgs.nixd
    pkgs.gnumake
    pkgs.gnupg
    pkgs.manix

    # It's just really neat
    pkgs.eza

    # Required by waybar and dunst
    pkgs.libnotify
  ];
}
