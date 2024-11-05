{ config, pkgs, ... }:
let
  screenshot-region = pkgs.writeShellApplication {
    name = "screenshot-region";

    runtimeInputs = [ pkgs.grim pkgs.slurp pkgs.wl-clipboard ];

    text = ''
      grim -g "$(slurp -d)" - | wl-copy && notify-send "Copied region to clipboard"
    '';
  };

  exit-if-all-closed = pkgs.writeShellApplication {
    name = "exit-if-all-closed";

    runtimeInputs = [ pkgs.sway pkgs.jq ];

    text = ''
      SWAYNAG_MAX_COUNT="3"
      FOCUSED_NODE_NAME="$(swaymsg -t get_tree | jq 'recurse(.nodes[]) | select (.focused == true).name')"

      if [[ "$(pgrep swaynag --count)" -ge "$SWAYNAG_MAX_COUNT" ]]; then
        notify-send "SHUTTING DOWN NOW!"
        shutdown now
        exit 0
      fi

      if [[ "$FOCUSED_NODE_NAME" =~ ^\"[0-9]+\"$ ]]; then
        swaynag -t warning -m 'Shutdown?' -b 'Yes' 'shutdown now';
        exit 0
      fi

      swaymsg kill
    '';
  };

  left-monitor = "LG Electronics LG ULTRAGEAR 112NTWGG8937";
  right-monitor = "AOC G2770 FWJE7HA000498";
in
{
  # See: https://github.com/nix-community/home-manager/issues/5379
  # TODO: FIXME: Delete this as soon as possible!
  wayland.windowManager.sway.checkConfig = false;

  home.packages = [ screenshot-region exit-if-all-closed ];

  wayland.windowManager.sway = {
    enable = true;
    xwayland = true;
    systemd.enable = true;

    # Effects and eye candy
    package = pkgs.swayfx;
    extraConfigEarly = ''
      layer_effects "waybar" "blur enable; shadows enable"

      blur enable

      shadows enable
      corner_radius 6
    '';

    config.gaps = {
      inner = 4;
      outer = 5;
    };

    config = {
      # Don't start waybar twice
      bars = [ ];

      # SUPER
      modifier = "Mod4";

      output = {
        ${left-monitor} = {
          mode = "2560x1440@164.956Hz";
          pos = "0 0";
        };
        ${right-monitor} = {
          mode = "1920x1080@144.001Hz";
          pos = "2560 0";
        };
      };

      input = {
        "type:pointer" = {
          accel_profile = "flat";
          # pointer_accel = "-0.5";
        };
      };

      workspaceOutputAssign = [
        { workspace = "1"; output = left-monitor; }
        { workspace = "2"; output = left-monitor; }
        { workspace = "3"; output = left-monitor; }
        { workspace = "4"; output = left-monitor; }
        { workspace = "5"; output = left-monitor; }

        { workspace = "6"; output = right-monitor; }
        { workspace = "7"; output = right-monitor; }
        { workspace = "8"; output = right-monitor; }
        { workspace = "9"; output = right-monitor; }
        { workspace = "10"; output = right-monitor; }
      ];

      assigns = {
        "1" = [{ app_id = "Alacritty"; }];
        "2" = [{ class = "obsidian"; }];
        "3" = [{ class = "Plexamp"; }];
        "5" = [{ class = "steam"; }];

        "6" = [{ app_id = "vesktop"; }];
        "10" = [{ app_id = "firefox"; }];
      };

      startup = [
        { command = "alacritty"; }
        { command = "obsidian"; }
        { command = "plexamp"; }
        { command = "steam"; }
        { command = "vesktop"; }
        { command = "firefox"; }
      ];

      floating.criteria = [
        { app_id = "pavucontrol"; }
        { app_id = "nemo"; }

        { app_id = "blueberry.py"; }

        { window_role = "pop-up"; }
        { window_role = "bubble"; }
        { window_role = "task_dialog"; }
        { window_role = "dialog"; }

        # Float all Steam windows except for Steam itself
        {
          class = "steam";
          title = "^(?!.*Steam).*$";
        }
      ];

      keybindings =
        let
          cfg = config.wayland.windowManager.sway.config;

          modifier = cfg.modifier;
        in
        {
          # Mimicking Windows behaviour to either kill individual windows or to shutdown the whole system
          "${modifier}+Shift+q" = "exec exit-if-all-closed";
          "${modifier}+Return" = "exec ${cfg.terminal}";
          "${modifier}+space" = "exec ${cfg.menu}";

          "${modifier}+Shift+s" = "exec screenshot-region";
          "${modifier}+e" = "exec nemo";

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
        };
    };
  };
}
