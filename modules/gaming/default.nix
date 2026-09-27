{ lib, ... }:
let
  make_game_window_rules = (
    window_regex: [
      "border_size 0, match:class ${window_regex}"
      "no_blur true, match:class ${window_regex}"
      "no_dim true, match:class ${window_regex}"
      "no_shadow true, match:class ${window_regex}"
      "no_anim true, match:class ${window_regex}"
      "workspace 1, match:class ${window_regex}"
      "immediate true, match:class ${window_regex}"
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
      windowrule = lib.lists.flatten (
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
