{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: let
  git-cram = pkgs.writeShellApplication {
    name = "git-cram";

    text = ''
      git add . ; git commit --amend --no-edit
    '';
  };

  show-pkg = pkgs.writeShellApplication {
    name = "show-pkg";

    runtimeInputs = [pkgs.nix pkgs.eza];

    text = ''
      PATHS="$(nix build "nixpkgs#$1" --print-out-paths --no-link)"

      for path in $PATHS; do
        eza "$path" --tree --level "''${2:-3}"
      done
    '';
  };
in {
  imports = [./packages];

  home.username = "aaron";
  home.homeDirectory = "/home/aaron";

  xdg = {
    enable = true;
    userDirs = {
      createDirectories = true;
      enable = true;
    };
  };

  home.packages = with pkgs; [
    # General
    google-chrome
    firefox
    spotify

    slack

    # Gaming
    mangohud
    protonup-qt
    r2modman

    # Productivity
    obsidian
    virtualbox
    jq

    # Utilities
    pavucontrol # Audio control
    cinnamon.nemo # File manager
    grimblast # Screen capture
    mpv # Media playback
    davinci-resolve

    # Scripts
    git-cram
    show-pkg
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

    # Force Qt applications to run through the Wayland platform plugin
    QT_QPA_PLATFORM = "wayland";
  };

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;

  # Give Home Manager the power to stop and start systemd services
  systemd.user.startServices = "sd-switch";

  # This value determines the Home Manager release that your configuration is
  # compatible with. This helps avoid breakage when a new Home Manager release
  # introduces backwards incompatible changes.
  #
  # You should not change this value, even if you update Home Manager. If you do
  # want to update the value, then make sure to first check the Home Manager
  # release notes.
  home.stateVersion = "23.11"; # Please read the comment before changing.
}
