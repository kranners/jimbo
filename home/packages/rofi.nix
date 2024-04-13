{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: {
  wayland.windowManager.sway.config.menu = "rofi -show drun -monitor -1";

  programs.rofi = {
    enable = true;
    package = pkgs.rofi-wayland;

    plugins = [pkgs.rofi-emoji pkgs.rofi-calc];

    location = "center";

    extraConfig = {
      modi = "window,drun,emoji,calc";

      icon-theme = "Oranchelo";
      show-icons = true;

      terminal = "${pkgs.foot}/bin/foot";

      location = 0;
      disable-history = false;
      hide-scrollbar = true;
      sidebar-mode = true;

      display-drun = "Apps";
      drun-display-format = "{icon} {name}";
      display-window = "Window";
    };
  };
}
