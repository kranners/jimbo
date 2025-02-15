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
    ./theme.nix
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
    ./walker.nix
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

  nix.settings = {
    extra-substituters = [
      "https://walker-git.cachix.org"
      "https://kranners.cachix.org"
    ];

    extra-trusted-public-keys = [
      "walker-git.cachix.org-1:vmC0ocfPWh0S/vRAQGtChuiZBTAe4wiKDeyyXM0/7pM="
      "kranners.cachix.org-1:ZuxIgFNLP2qrpRXPKGMV1U+GErsAFU4Em4sqoOkJ0no="
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
