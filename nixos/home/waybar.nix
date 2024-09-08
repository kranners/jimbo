{ pkgs, lib, ... }: {
  systemd.user.services.workstyle = {
    Unit = { Description = "Auto rename workspaces based on what's in them"; };
    Install = { WantedBy = [ "sway-session.target" ]; };
    Service = {
      ExecStart = "${pkgs.workstyle}/bin/workstyle";
      Restart = "always";
      RestartSec = "3";
    };
  };

  wayland.windowManager.sway.config.startup = [
    {
      command = "systemctl --user restart waybar";
      always = true;
    }

    {
      command = "systemctl --user restart workstyle";
      always = true;
    }
  ];

  xdg.configFile = {
    workstyle = {
      target = "./workstyle/config.toml";

      text = ''
        # Config for workstyle
        #
        # Format:
        # "pattern" = "icon"
        #
        # The pattern will be used to match against the application name class_id or WM_CLASS.
        # The icon will be used to represent that application.
        #
        # Note if multiple patterns are present in the same application name;
        # precedence is given in order of apparition in this file.

        # Glyphs can be found at the Nerd Font cheat sheet:
        # https://www.nerdfonts.com/cheat-sheet

        "foot" = ""
        "alacritty" = ""
        "firefox" = ""
        "nemo" = ""
        "spotify" = "󰓇"
        "discord" = "󰙯"
        "steam" = "󰓓"
        "obsidian" = ""
        "wine" = "🍷"
        "obs" = "󰕧"
        "mpv" = ""

        "lutris" = ""
        "battle.net" = ""
        "hearthstone" = "󱢡"
        "google chrome" = ""
        "plexamp" = "󰚺"

        [other]
        fallback_icon = "🤨"
        deduplicate_icons = false
        separator = " "
      '';
    };
  };

  programs.waybar = {
    enable = true;
    systemd.enable = true;

    settings.main =
      let
        icons = {
          audio = "󰓃";
          clock = "";
          bluetooth = "";
          tray = "󰇙";

          divider = "|";

          space-left = " ";
          space-right = " ";
        };

        power-options = {
          shutdown = {
            icon = "";
            action = "systemctl poweroff";
          };
          reboot = {
            icon = "";
            action = "systemctl reboot";
          };
          logout = {
            icon = "";
            action = "sway exit";
          };
          firmware = {
            icon = "";
            action = "systemctl reboot --firmware-setup";
          };
        };

        mkPowerModule = (key: option: {
          name = "custom/power-${key}";
          value = {
            format = " ${option.icon} ";
            tooltip = false;
            on-click = option.action;
          };
        });

        mkIconModule = (key: icon: {
          name = "custom/icon-${key}";
          value = {
            format = icon;
            tooltip = false;
          };
        });

        icon-modules = lib.mapAttrs' mkIconModule icons;
        power-modules = lib.mapAttrs' mkPowerModule power-options;
      in
      icon-modules // power-modules //
      {
        layer = "top";

        modules-left = [
          "group/power"
          "custom/icon-space-right"
        ];

        modules-center = [
          "sway/workspaces"
        ];

        modules-right = [
          "custom/icon-space-left"
          "group/sys-tray"
          "custom/icon-audio"
          "pulseaudio"
          "custom/icon-bluetooth"
          "bluetooth"
          "custom/icon-space-left"
          "network"
          "custom/icon-clock"
          "clock"
          "custom/notifications"
        ];

        "sway/workspaces" = {
          format = "{name}";
        };

        "custom/notifications" = {
          tooltip = false;
          format = "{icon}";
          format-icons = {
            notification = "";
            none = "";
            dnd-notification = "";
            dnd-none = "";
            inhibited-notification = "";
            inhibited-none = "";
            dnd-inhibited-notification = "";
            dnd-inhibited-none = "";
          };

          return-type = "json";
          exec-if = "which swaync-client";
          exec = "swaync-client -swb";
          on-click = "swaync-client -t -sw";
          on-click-right = "swaync-client -d -sw";
          escape = true;
        };

        "group/power" = {
          orientation = "horizontal";
          drawer = {
            transition-duration = 600;
            transition-left-to-right = true;
          };
          modules = [
            "custom/power-shutdown"
            "custom/icon-divider"
            "custom/power-reboot"
            "custom/icon-divider"
            "custom/power-logout"
            "custom/icon-divider"
            "custom/power-firmware"
          ];
        };

        tray = {
          icon-size = 18;
          spacing = 12;
        };

        "group/sys-tray" = {
          orientation = "horizontal";
          drawer = {
            transition-duration = 600;
            transition-left-to-right = false;
          };
          modules = [
            "custom/icon-tray"
            "tray"
          ];
        };

        clock = {
          format = "{:%I:%M:%S %p}";
          interval = 1;
        };

        pulseaudio = {
          format = "{volume}%";
          tooltip = false;
          scroll-step = 1;
          on-click = "${pkgs.pavucontrol}/bin/pavucontrol";
        };

        bluetooth = {
          format = "{status}";
          on-click = "${pkgs.blueberry}/bin/blueberry";
        };

        network = {
          interface = "enp42s0";
          format = "{ifname}";
          format-wifi = " {essid} ({signalStrength}%)";
          format-ethernet = "󰈀 {ipaddr}";
        };
      };

    style =
      let
        space-sm = "6px";
        space-md = "12px";
        space-lg = "16px";
      in
      ''
        @define-color bg #11111B;
        @define-color bg-light #1E1E2E;
        @define-color border #313244;
        @define-color fg #CDD6F4;
        @define-color accent #B4BEFE;
        @define-color inactive #45475A;

        * {
            font-family: "JetBrainsMono Nerd Font","Font Awesome 6";
            font-size: ${space-lg};
            min-height: 30px;
            transition: linear .3s;
        }

        #workspaces {
            margin-bottom: ${space-sm};
            margin-right: ${space-lg};
            margin-top: ${space-sm};
            border-radius: ${space-sm};
            padding-left: ${space-sm};
            padding-right: ${space-sm};
        }

        #custom-notifications {
            border-radius: ${space-sm};
            margin: ${space-sm} ${space-md} ${space-sm} 0;
            padding-right: ${space-md};
            padding-left: ${space-md};
        }

        #bluetooth,
        #clock,
        #pulseaudio,
        #network,
        #workspaces {
            background: @bg-light;
        }

        #workspaces button {
            padding: 0 ${space-md};
            color: @inactive;
        }

        #workspaces button.focused {
            color: @accent;
        }

        #tray,
        #window {
            background-color: @bg-light;
            color: @fg;
        }

        #window {
            border-radius: ${space-sm};
            margin-bottom: ${space-sm};
            margin-right: ${space-lg};
            margin-top: ${space-sm};
            padding-left: ${space-md};
            padding-right: ${space-md};
        }

        #tray {
            border-radius: 0;
            margin-right: 0;
        }

        #custom-power-firmware,
        #custom-power-logout,
        #custom-power-reboot,
        #custom-suspend,
        #network,
        #tray {
            margin-bottom: ${space-sm};
            margin-top: ${space-sm};
            padding-left: ${space-md};
            padding-right: ${space-md}
        }

        #bluetooth,
        #clock,
        #custom-icon-tray,
        #pulseaudio {
            margin-bottom: ${space-sm};
            margin-top: ${space-sm};
            padding-right: ${space-md};
        }

        #custom-icon-audio,
        #custom-icon-bluetooth,
        #custom-icon-clock {
            padding-left: ${space-md};
            padding-right: ${space-md};
        }

        #custom-icon-tray,
        #network {
            padding-left: ${space-sm};
        }

        #custom-icon-divider {
            margin-bottom: ${space-sm};
            margin-top: ${space-sm};
        }

        #bluetooth,
        #clock,
        #custom-icon-tray,
        #network,
        #pulseaudio {
            border-radius: 0 ${space-sm} ${space-sm} 0;
            margin-right: ${space-lg};
        }

        #custom-power-shutdown {
            margin-bottom: ${space-sm};
            margin-top: ${space-sm};
            padding-left: ${space-md};
            padding-right: ${space-md};
            border-radius: ${space-sm} 0 0 ${space-sm};
            margin-left: ${space-lg};
        }

        #custom-icon-space {
            background-color: @bg-light;
        }

        #custom-icon-audio,
        #custom-icon-bluetooth,
        #custom-icon-clock,
        #custom-icon-space {
            border-radius: ${space-sm} 0 0 ${space-sm};
            border-right: none;
            margin-bottom: ${space-sm};
            margin-top: ${space-sm};
        }

        #custom-icon-space-left,
        #custom-icon-space-right {
            margin-bottom: ${space-sm};
            margin-top: ${space-sm};
            background-color: @bg-light;
        }

        #custom-icon-space-right {
            border-radius: 0 ${space-sm} ${space-sm} 0;
            border-left: none;
        }

        #custom-icon-space-left {
            border-radius: ${space-sm} 0 0 ${space-sm};
            border-right: none;
        }

        #bluetooth,
        #clock,
        #pulseaudio {
            padding-left: 0;
            color: @fg;
        }

        window#waybar {
            background-color: transparent;
        }

        #custom-icon-audio,
        #custom-icon-bluetooth,
        #custom-icon-clock,
        #custom-icon-divider,
        #custom-icon-tray,
        #custom-notifications,
        #custom-power-firmware,
        #custom-power-logout,
        #custom-power-reboot,
        #custom-power-shutdown,
        #custom-suspend {
            background-color: @bg-light;
            color: @accent
        }
      '';
  };
}
