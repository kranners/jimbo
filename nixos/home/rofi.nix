{ config
, pkgs
, lib
, inputs
, ...
}: {
  wayland.windowManager.sway.config.menu = "rofi -show drun -monitor -1";

  programs.rofi = {
    enable = true;
    package = pkgs.rofi-wayland;

    plugins = [
      pkgs.rofi-emoji
      pkgs.rofi-calc
      (pkgs.callPackage ../../shared/packages/rofi-games { })
    ];

    location = "center";

    extraConfig = {
      modi = "window,drun,emoji,calc,games";

      icon-theme = "Oranchelo";

      show-icons = true;

      terminal = "${pkgs.foot}/bin/foot";

      location = 0;
      disable-history = false;
      hide-scrollbar = true;
      sidebar-mode = true;

      drun-display-format = "{icon} {name}";

      display-drun = "Apps";
      display-window = "Window";
      display-games = "Games";
    };
  };
}
