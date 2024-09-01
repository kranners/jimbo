{ pkgs, ... }: {
  wayland.windowManager.sway.config.menu = "rofi -show drun -monitor -1";

  programs.rofi = {
    enable = true;
    package = pkgs.rofi-wayland;

    plugins = [
      pkgs.rofi-emoji
      pkgs.rofi-calc
    ];

    location = "center";

    theme = "material";

    extraConfig = {
      modi = "window,drun,emoji,calc";

      icon-theme = "Oranchelo";

      show-icons = true;

      terminal = "alacritty";

      location = 0;
      disable-history = false;
      hide-scrollbar = true;
      sidebar-mode = true;

      drun-display-format = "{icon} {name}";

      display-drun = "Apps";
      display-window = "Window";
    };
  };
}
