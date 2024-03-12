{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: {
  imports = [./packages];

  home.username = "aaron";
  home.homeDirectory = "/home/aaron";

  home.packages = with pkgs; [
    # General
    spotify
    google-chrome
    kitty

    # Chat clients
    vesktop
    slack

    # Gaming
    steam
    lutris
    wine

    # Productivity
    obsidian
    vscode
    _1password-gui

    # Hyprland setup
    capitaine-cursors # Cursor theme
    swww # Wallpaper
    dunst # Notifications
    # Rofi configured seperately
    # Waybar configured seperately

    # Utilities
    pavucontrol # Audio control
    xfce.thunar # File manager
    grimblast # Screen capture
    wf-recorder # Screen recording
    vlc # Media playback
    cliphist # Clipboard manager
  ];

  gtk.cursorTheme = {
    name = "capitaine-cursors";
    package = pkgs.capitaine-cursors;
  };

  # Home Manager is pretty good at managing dotfiles. The primary way to manage
  # plain files is through 'home.file'.
  home.file = {
    # # Building this configuration will create a copy of 'dotfiles/screenrc' in
    # # the Nix store. Activating the configuration will then make '~/.screenrc' a
    # # symlink to the Nix store copy.
    # ".screenrc".source = dotfiles/screenrc;
  };

  home.sessionVariables = {
    EDITOR = "nvim";
  };

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;

  # This value determines the Home Manager release that your configuration is
  # compatible with. This helps avoid breakage when a new Home Manager release
  # introduces backwards incompatible changes.
  #
  # You should not change this value, even if you update Home Manager. If you do
  # want to update the value, then make sure to first check the Home Manager
  # release notes.
  home.stateVersion = "23.11"; # Please read the comment before changing.
}
