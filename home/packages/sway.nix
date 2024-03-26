{
  config,
  pkgs,
  inputs,
  lib,
  ...
}: {
  wayland.windowManager.sway = {
    enable = true;
    xwayland = true;

    config = {
      menu = "${pkgs.rofi}/bin/rofi -show drun";
      terminal = "${pkgs.foot}/bin/foot";

      startup = [
        {
          command = "systemctl --user restart waybar";
          always = true;
        }
      ];

      # Don't start waybar twice
      bars = [];

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

      gaps = {
        inner = 3;
        outer = 5;
      };

      keybindings = let
        cfg = config.wayland.windowManager.sway.config;

        modifier = cfg.modifier;
      in {
        "${modifier}+Return" = "exec ${cfg.terminal}";
        "${modifier}+Shift+q" = "kill";
        "${modifier}+space" = "exec ${cfg.menu}";

        "${modifier}+${cfg.left}" = "focus left";
        "${modifier}+${cfg.down}" = "focus down";
        "${modifier}+${cfg.up}" = "focus up";
        "${modifier}+${cfg.right}" = "focus right";

        "${modifier}+Shift+${cfg.left}" = "move left";
        "${modifier}+Shift+${cfg.down}" = "move down";
        "${modifier}+Shift+${cfg.up}" = "move up";
        "${modifier}+Shift+${cfg.right}" = "move right";

        "${modifier}+f" = "fullscreen toggle";
        "${modifier}+Shift+f" = "floating toggle";

        "${modifier}+w" = "layout tabbed";
        "${modifier}+e" = "layout toggle split";

        "${modifier}+1" = "workspace number 1";
        "${modifier}+2" = "workspace number 2";
        "${modifier}+3" = "workspace number 3";
        "${modifier}+4" = "workspace number 4";
        "${modifier}+5" = "workspace number 5";
        "${modifier}+6" = "workspace number 6";
        "${modifier}+7" = "workspace number 7";
        "${modifier}+8" = "workspace number 8";
        "${modifier}+9" = "workspace number 9";
        "${modifier}+0" = "workspace number 10";

        "${modifier}+Shift+1" = "move container to workspace number 1";
        "${modifier}+Shift+2" = "move container to workspace number 2";
        "${modifier}+Shift+3" = "move container to workspace number 3";
        "${modifier}+Shift+4" = "move container to workspace number 4";
        "${modifier}+Shift+5" = "move container to workspace number 5";
        "${modifier}+Shift+6" = "move container to workspace number 6";
        "${modifier}+Shift+7" = "move container to workspace number 7";
        "${modifier}+Shift+8" = "move container to workspace number 8";
        "${modifier}+Shift+9" = "move container to workspace number 9";
        "${modifier}+Shift+0" = "move container to workspace number 10";

        "${modifier}+Shift+c" = "reload";
        "${modifier}+Shift+e" = "exec swaynag -t warning -m 'You pressed the exit shortcut. Do you really want to exit sway? This will end your Wayland session.' -b 'Yes, exit sway' 'swaymsg exit'";

        "${modifier}+r" = "mode resize";
      };
    };
  };
}
