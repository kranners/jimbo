{ lib, ... }:
let
  make_game_window_rules = (
    window_regex: [
      "prop noborder,class:${window_regex}"
      "prop noblur,class:${window_regex}"
      "prop nodim,class:${window_regex}"
      "prop noshadow,class:${window_regex}"
      "prop noanim,class:${window_regex}"
      "workspace 1,class:${window_regex}"
      "immediate,class:${window_regex}"
    ]
  );
in
{
  darwinSystemModule.homebrew.casks = [ "jagex" ];

  nixosSystemModule = {
    programs = {
      steam = {
        enable = true;
        localNetworkGameTransfers.openFirewall = true;
      };

      gamemode.enable = true;
    };
  };

  nixosHomeModule = { pkgs, ... }: {
    home.packages = [
      pkgs.protonup-qt
      pkgs.r2modman
      pkgs.pokemmo-installer
      pkgs.prismlauncher
      pkgs.bolt-launcher
      pkgs.lutris
    ];

    wayland.windowManager.hyprland.settings = {
      windowrulev2 = lib.lists.flatten (
        lib.lists.map (window_regex: make_game_window_rules window_regex) [
          "^gamescope$"
          "^steam_app_\\d+$"
          "^overwatch.exe$"
        ]
      );

      exec-once = [
        "app2unit -- ${pkgs.steam}/share/applications/steam.desktop"
      ];

      bind = [
        "$mod, S, exec, steam"
      ];
    };
  };
}
