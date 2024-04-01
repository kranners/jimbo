{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: {
  programs.rofi = {
    enable = true;
    
    plugins = [pkgs.rofi-emoji pkgs.rofi-calc];

    location = "center";

    extraConfig = {
      modi = "window,run,drun,emoji,calc";
      icon-theme = "Oranchelo";
      show-icons = true;
      terminal = "${pkgs.foot}/bin/foot";
      drun-display-format = "{icon} {name}";
      location = 0;
      disable-history = false;
      hide-scrollbar = true;

      display-drun = "Apps";
      display-run = "Run";
      display-window = "Window";

      sidebar-mode = true;
    };
  };
}
