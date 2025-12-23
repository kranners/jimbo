{
  nixosHomeModule = {
    wayland.windowManager.hyprland.settings."$launcher" = "rofi -show drun -run-command 'uwsm app -- {cmd}'";

    programs.rofi = {
      enable = true;

      location = "center";

      theme = "material";

      extraConfig = {
        modi = "window,drun";

        icon-theme = "Oranchelo";

        show-icons = true;

        terminal = "ghostty";

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
