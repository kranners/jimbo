{ pkgs, ... }: {
  imports = [
    ./user.nix
    ./scripts.nix
    ./state-versions.nix
  ];

  home.home.packages = [
    # Media
    pkgs.spotify
    pkgs.plexamp

    # Gaming
    pkgs.mangohud
    pkgs.protonup-qt
    pkgs.r2modman

    # Productivity
    pkgs.obsidian
    pkgs.ripgrep
    pkgs.jq

    # Utilities
    pkgs.pavucontrol # Audio control
    pkgs.nemo-with-extensions # File manager
    pkgs.grimblast # Screen capture
    pkgs.mpv # Media playback
    pkgs.davinci-resolve
    pkgs.blueberry # Bluetooth manager
    pkgs.wl-clipboard # Clipboard manager
    pkgs.helvum # Multi-audio output
  ];

  environment.systemPackages = with pkgs; [
    nh
    nixfmt-rfc-style
    gnumake
    gnupg
    manix
    nurl
    eza
    btop
    htop
    vim

    # Required libs for background services
    libnotify
    pipewire
  ];
}
