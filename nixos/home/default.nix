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
    ./waybar.nix
    ./swaync.nix
    ./vesktop.nix
    ./lutris.nix
    ./avizo.nix
    ./firefox.nix
    ./plexamp.nix
    ./ungoogled-chromium.nix
    ./mangohud.nix
    ./wayvnc.nix
    ./wpaperd.nix
    ./obsidian-service.nix
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
}
