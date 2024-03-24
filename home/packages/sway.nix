{
  config,
  pkgs,
  inputs,
  ...
}: {
  wayland.windowManager.sway = {
    enable = true;
    xwayland = true;

    config = {
      menu = "${pkgs.rofi}/bin/rofi -show drun";
      terminal = "${pkgs.foot}/bin/foot";

      # SUPER
      modifier = "Mod4";

      # Configure monitors
      output = {
        "LG Electronics LG ULTRAGEAR 112NTWGG8937" = {
          mode = "2560x1440@164.956Hz";
          pos = "0 0";
        };
        "AOC G2770 0x000001F2" = {
          mode = "1920x1080@144.001Hz";
          pos = "2560 0";
        };
      };
    };
  };
}
