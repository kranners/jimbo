{ pkgs, ... }:
let
  wine-local = pkgs.writeShellApplication {
    name = "wine-local";

    text = ''
      WINEPREFIX="$PWD" wine "$@"
    '';
  };
in
{
  imports = [
    ./git.nix
    ./sway.nix
    ./rofi.nix
    ./waybar.nix
    ./theme.nix
    ./swaync.nix
    ./vesktop.nix
    ./lutris.nix
    ./obs-studio.nix
    ./avizo.nix
    ./easyeffects.nix
    ./firefox.nix
    ./plexamp.nix
    ./ungoogled-chromium.nix
    ./mangohud.nix
    ./hyprland.nix
    ./wayvnc.nix
    ./wpaperd.nix
    ./anyrun.nix
  ];

  home.username = "aaron";
  home.homeDirectory = "/home/aaron";

  xdg = {
    enable = true;
    userDirs = {
      createDirectories = true;
      enable = true;
    };
  };

  home.packages = [
    # General
    pkgs.google-chrome

    # Media
    pkgs.spotify
    pkgs.plexamp
    pkgs.nicotine-plus

    # Gaming
    pkgs.protonup-qt
    pkgs.r2modman

    # Productivity
    pkgs.obsidian
    pkgs.ripgrep
    pkgs.jq
    pkgs.nh

    # Utilities
    pkgs.pavucontrol # Audio control
    pkgs.nemo-with-extensions # File manager
    pkgs.grimblast # Screen capture
    pkgs.mpv # Media playback
    pkgs.blueberry # Bluetooth manager
    pkgs.wl-clipboard # Clipboard manager
    pkgs.helvum # Multi-audio output

    # Scripts
    wine-local
  ];

  home.sessionVariables = {
    # Force Qt applications to run through the Wayland platform plugin
    QT_QPA_PLATFORM = "wayland";
  };

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;

  # Give Home Manager the power to stop and start systemd services
  systemd.user.startServices = "sd-switch";

  nix.settings = {
    extra-substituters = [
      "https://anyrun.cachix.org"
    ];

    extra-trusted-public-keys = [
      "anyrun.cachix.org-1:pqBobmOjI7nKlsUMV25u9QHa9btJK65/C8vnO3p346s="
    ];
  };

  # This value determines the Home Manager release that your configuration is
  # compatible with. This helps avoid breakage when a new Home Manager release
  # introduces backwards incompatible changes.
  #
  # You should not change this value, even if you update Home Manager. If you do
  # want to update the value, then make sure to first check the Home Manager
  # release notes.
  home.stateVersion = "23.11"; # Please read the comment before changing.
}
