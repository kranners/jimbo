{
  config,
  pkgs,
  inputs,
  ...
}: {
  imports = [./programs ./desktop];

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

    # Hyprland setup
    waybar
    swww
    dunst
    rofi-wayland

    # Utilities
    pavucontrol
    xfce.thunar
  ];

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
