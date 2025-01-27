{ pkgs, inputs, ... }: {
  wayland.windowManager.hyprland.settings."$terminal" = "rofi -show drun -monitor -1";

  programs.rofi = {
    enable = true;
    package = pkgs.rofi-wayland;

    plugins = [
      (pkgs.callPackage ../../shared/packages/rofi-games { })
    ];

    location = "center";

    theme = "${inputs.rofi-themes-collection}/spotlight.rasi";

    extraConfig = {
      modi = "window,drun,games";

      icon-theme = "Oranchelo";

      show-icons = true;

      terminal = "alacritty";

      location = 0;
      disable-history = false;
      hide-scrollbar = true;
      sidebar-mode = true;

      drun-display-format = "{icon} {name}";

      display-window = "Window";
      display-drun = "Apps";
      display-games = "Games";
    };
  };
}
