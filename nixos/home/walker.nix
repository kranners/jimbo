{
  wayland.windowManager.hyprland.settings."$menu" = "walker";

  programs.walker = {
    enable = true;
    runAsService = true;
  };
}
