{ pkgs, ... }: {
  nixosHomeModule = {
    wayland.windowManager.hyprland.settings."$launcher" = "rofi -show drun -monitor -1";

    programs.rofi = {
      enable = true;
      package = pkgs.rofi-wayland;

      location = "center";

      theme = "material";

      extraConfig = {
        modi = "window,drun";

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
      };
    };
  };
}
