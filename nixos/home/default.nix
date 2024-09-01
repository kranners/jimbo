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
    ./wallpaper.nix
    ./inactive-windows-transparency.nix
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
