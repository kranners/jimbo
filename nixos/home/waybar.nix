{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: {
  systemd.user.services.workstyle = {
    Unit = {Description = "Auto rename workspaces based on what's in them";};
    Install = {WantedBy = ["sway-session.target"];};
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

  xdg.configFile.workstyle = {
    target = "./workstyle/config.toml";

    text = ''
      # Config for workstyle
      #
      # Format:
      # "pattern" = "icon"
      #
      # The pattern will be used to match against the application name, class_id or WM_CLASS.
      # The icon will be used to represent that application.
      #
      # Note if multiple patterns are present in the same application name,
      # precedence is given in order of apparition in this file.

      # Glyphs can be found at the Nerd Font cheat sheet:
      # https://www.nerdfonts.com/cheat-sheet

      "code" = "󰨞"
      "foot" = ""
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

      [other]
      fallback_icon = "🤨"
      deduplicate_icons = false
      separator = ": "
    '';
  };

  programs.waybar = {
    enable = true;

    systemd.enable = true;

    settings = [
      {
        height = 30;
        layer = "top";
        position = "top";

        modules-left = ["pulseaudio" "clock"];
        modules-center = ["sway/workspaces"];
        modules-right = ["tray"];

        clock = {
          format-alt = "{:%Y-%m-%d}";
          tooltip-format = "{:%Y-%m-%d | %H:%M}";
        };

        pulseaudio = {
          format = "{icon} {volume}%";
          format-muted = "";
          on-click = "${pkgs.pavucontrol}/bin/pavucontrol";
          format-icons = ["" "" ""];
        };
      }
    ];
  };
}
