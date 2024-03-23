{
  programs.waybar = {
    enable = true;

    settings = [
      {
        height = 20;
        layer = "top";
        position = "top";
        tray = {spacing = 0;};
        modules-left = ["hyprland/workspaces"];
        modules-center = ["hyprland/window"];
        modules-right = [
          "pulseaudio"
          "clock"
          "tray"
        ];
        clock = {
          format-alt = "{:%Y-%m-%d}";
          tooltip-format = "{:%Y-%m-%d | %H:%M}";
        };
        pulseaudio = {
          format = "{volume}% {icon} {format_source}";
          format-bluetooth = "{volume}% {icon} {format_source}";
          format-bluetooth-muted = " {icon} {format_source}";
          format-icons = {
            car = "";
            default = ["" "" ""];
            handsfree = "";
            headphones = "";
            headset = "";
            phone = "";
            portable = "";
          };
          format-muted = " {format_source}";
          format-source = "{volume}% ";
          format-source-muted = "";
          on-click = "pavucontrol";
        };
      }
    ];
  };
}
