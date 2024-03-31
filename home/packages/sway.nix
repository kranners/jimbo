{
  config,
  pkgs,
  inputs,
  lib,
  ...
}: let
  screenshot-region = pkgs.writeShellApplication {
    name = "screenshot-region";

    runtimeInputs = [pkgs.grim pkgs.slurp pkgs.wl-clipboard];

    text = ''
      grim -g "$(slurp -d)" - | wl-copy && notify-send "Copied region to clipboard"
    '';
  };

  exit-if-all-closed = pkgs.writeShellApplication {
    name = "exit-if-all-closed";

    runtimeInputs = [pkgs.sway pkgs.jq];

    text = ''
      FOCUSED_NODE="$(swaymsg -t get_tree | jq 'recurse(.nodes[]) | select (.nodes[].focused == true).nodes[0]')"
      FOCUSED_NODE_NAME="$(echo "$FOCUSED_NODE" | jq '.name')"

      if [[ "$FOCUSED_NODE_NAME" =~ ^\"[0-9]+\"$ ]]; then
        swaynag -t warning -m 'Shutdown?' -b 'Yes' 'shutdown now';
        return 0
      fi

      FOCUSED_NODE_PID="$(echo "$FOCUSED_NODE" | jq '.pid')"
      kill "$FOCUSED_NODE_PID"
    '';
  };
in {
  home.packages = [screenshot-region exit-if-all-closed];

  wayland.windowManager.sway = {
    enable = true;
    xwayland = true;

    config = {
      menu = "${pkgs.rofi}/bin/rofi -show drun";
      terminal = "${pkgs.foot}/bin/foot";

      # Auto start
      startup = [
        {
          command = "systemctl --user restart waybar";
          always = true;
        }

        {
          command = "${pkgs.stylish}/bin/styli.sh -y -s nature,space,architecture --width 2560 --height 1440";
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

      # Define when windows should float
      floating.criteria = [
        {app_id = "pavucontrol";}

        {window_role = "pop-up";}
        {window_role = "bubble";}
        {window_role = "task_dialog";}
        {window_role = "dialog";}

        # Float all Steam windows except for Steam itself
        {
          class = "steam";
          title = "^(?!.*Steam).*$";
        }
      ];

      keybindings = let
        cfg = config.wayland.windowManager.sway.config;

        modifier = cfg.modifier;
      in {
        # Mimicking Windows behaviour to either kill individual windows or to shutdown the whole system
        "${modifier}+Shift+q" = "exec exit-if-all-closed";
        "${modifier}+Return" = "exec ${cfg.terminal}";
        "${modifier}+space" = "exec ${cfg.menu}";

        "${modifier}+Shift+s" = "exec screenshot-region";

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

        "${modifier}+t" = "layout tabbed";
        "${modifier}+Shift+t" = "layout toggle split";

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

        "${modifier}+r" = "mode resize";
      };
    };
  };
}
