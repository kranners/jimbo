{ config, pkgs, inputs, ... }: {
  imports = [ ./gnupg.nix ./zsh.nix ./steam.nix ./opengl.nix ];

  environment.systemPackages = [
    # Nix development tools
    pkgs.nixfmt-rfc-style
    pkgs.nil
    pkgs.gnumake
    pkgs.gnupg
    pkgs.manix

    # It's just really neat
    pkgs.eza

    # Required by waybar and dunst
    pkgs.libnotify

    # Required for screensharing
    pkgs.pipewire
  ];
}
