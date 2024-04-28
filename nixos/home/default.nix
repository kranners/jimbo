{ config, pkgs, lib, inputs, ... }:
let
  git-cram = pkgs.writeShellApplication {
    name = "git-cram";

    text = ''
      git add . ; git commit --amend --no-edit
    '';
  };

  show-pkg = pkgs.writeShellApplication {
    name = "show-pkg";

    runtimeInputs = [ pkgs.nix pkgs.eza ];

    text = ''
      PATHS="$(nix build "nixpkgs#$1" --print-out-paths --no-link)"

      for path in $PATHS; do
        eza "$path" --tree --level "''${2:-3}"
      done
    '';
  };

  find-pkg = pkgs.writeShellApplication {
    name = "find-pkg";

    text = ''
      nix-store --query --requisites /run/current-system | cut -d- -f2- | sort -u | grep "$1"
    '';
  };
in
{
  imports = [
    ../../shared/home/neovim

    ./git.nix
    ./sway.nix
    ./rofi.nix
    ./waybar.nix
    ./zsh.nix
    ./theme.nix
    ./dunst.nix
    ./vesktop.nix
    ./lutris.nix
    ./obs-studio.nix
    ./avizo.nix
    ./easyeffects.nix
    ./foot.nix
    ./vscode.nix
    ./firefox.nix
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

  home.packages = with pkgs; [
    # General
    google-chrome
    spotify

    # Gaming
    mangohud
    protonup-qt
    r2modman

    # Productivity
    obsidian
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
    find-pkg
  ];

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
