{ pkgs, lib, ... }:
let
  exit-if-all-closed = pkgs.writeShellApplication {
    name = "exit-if-all-closed";

    runtimeInputs = [ pkgs.sway ];
    bashOptions = [ ];

    text = ''
      SWAYNAG_MAX_COUNT="3"
      SWAYNAG_CURRENT="$(pgrep swaynag --count)"
      SWAYNAG_DISPLAY_CURRENT="$(( SWAYNAG_CURRENT + 1 ))"

      if [[ "$SWAYNAG_CURRENT" -ge "$SWAYNAG_MAX_COUNT" ]]; then
        shutdown now
        exit 0
      fi

      if [[ "$(hyprctl activewindow)" == "Invalid" ]]; then
        swaynag -t warning -m "Shutdown $SWAYNAG_DISPLAY_CURRENT/$SWAYNAG_MAX_COUNT"
        exit 0
      fi

      hyprctl dispatch killactive
    '';
  };

  gapless-mode = pkgs.writeShellApplication {
    name = "gapless-mode";

    bashOptions = [ ];

    text = ''
      PADDING_VALUE=10

      if systemctl --user --quiet is-active waybar; then
        systemctl --user stop waybar
        hyprctl keyword general:gaps_in 0
        hyprctl keyword general:gaps_out 0
        exit 0
      fi

      systemctl --user start waybar
      hyprctl keyword general:gaps_in $PADDING_VALUE
      hyprctl keyword general:gaps_out $PADDING_VALUE
    '';
  };

  make_game_window_rules = (
    window_regex: [
      "prop noborder,class:${window_regex}"
      "prop noblur,class:${window_regex}"
      "prop nodim,class:${window_regex}"
      "prop noshadow,class:${window_regex}"
      "prop noanim,class:${window_regex}"
      "workspace 1,class:${window_regex}"
      "immediate,class:${window_regex}"
    ]
  );
in
{
  nixosHomeModule.home.packages = [
    exit-if-all-closed
    gapless-mode
    pkgs.grim
    pkgs.slurp
    pkgs.wl-clipboard
  ];

  nixosSystemModule = {
    programs.hyprland = {
      enable = true;
      withUWSM = true;
    };

    programs.uwsm.enable = true;

    services.greetd = {
      enable = true;
      settings = {
        default_session = {
          command = "uwsm start hyprland-uwsm.desktop";
          user = "aaron";
        };
      };
    };

    environment.sessionVariables.NIXOS_OZONE_WL = "1";
  };

  nixosHomeModule.wayland.windowManager.hyprland = {
    enable = true;

    settings = {
      "$mod" = "SUPER";

      general = {
        layout = "master";
      };

      ecosystem.no_update_news = true;

      master = {
        orientation = "center";
        slave_count_for_center_master = 0;
        always_keep_position = true;
      };

      device = [
        {
          name = "compx-2.4g-wireless-receiver";
          accel_profile = "flat";
          sensitivity = "0";
        }

        {
          name = "compx-2.4g-dual-mode-mouse";
          accel_profile = "flat";
          sensitivity = "0";
        }
      ];

      windowrulev2 = lib.lists.flatten (
        lib.lists.map (window_regex: make_game_window_rules window_regex) [
          "^gamescope$"
          "^steam_app_\\d+$"
          "^overwatch.exe$"
        ]
      );

      exec-once = lib.lists.map (x: "app2unit -- " + x) [
        "${pkgs.vesktop}/share/applications/vesktop.desktop"
        "${pkgs.steam}/share/applications/steam.desktop"
      ];

      bindm = [
        "$mod, mouse:272, movewindow"
        "$mod, mouse:273, resizewindow"
      ];

      bind = [
        "$mod, SPACE, exec, $launcher"
        "$mod, D, exec, eww open dashboard --screen $(hyprctl monitors -j | jq '.[] | select(.focused) | .id')"
        "$mod SHIFT, D, exec, eww close-all"

        "$mod, RETURN, exec, $terminal"
        "$mod, E, exec, $fileManager"

        "$mod SHIFT, S, exec, grim -g \"$(slurp -d)\" - | wl-copy && notify-send 'Copied to clipboard'"

        "$mod SHIFT, Q, exec, exit-if-all-closed"

        "$mod, G, exec, gapless-mode"

        "$mod, F, fullscreen"
        "$mod SHIFT, F, togglefloating"

        "$mod, O, exec, obsidian"
        "$mod, S, exec, steam"
        "$mod, Y, exec, spotify"
        "$mod, B, exec, vivaldi"
        "$mod, V, exec, vesktop"
        "$mod, P, exec, plexamp"
        "$mod, C, exec, chromium"

        "$mod, H, movefocus, l"
        "$mod, J, movefocus, d"
        "$mod, K, movefocus, u"
        "$mod, L, movefocus, r"
        "$mod SHIFT, H, movewindow, l"
        "$mod SHIFT, J, movewindow, d"
        "$mod SHIFT, K, movewindow, u"
        "$mod SHIFT, L, movewindow, r"

        "$mod, 1, workspace, 1"
        "$mod, 2, workspace, 2"
        "$mod, 3, workspace, 3"
        "$mod, 4, workspace, 4"
        "$mod, 5, workspace, 5"
        "$mod, 6, workspace, 6"
        "$mod, 7, workspace, 7"
        "$mod, 8, workspace, 8"
        "$mod, 9, workspace, 9"
        "$mod, 0, workspace, 10"

        "$mod SHIFT, 1, movetoworkspacesilent, 1"
        "$mod SHIFT, 2, movetoworkspacesilent, 2"
        "$mod SHIFT, 3, movetoworkspacesilent, 3"
        "$mod SHIFT, 4, movetoworkspacesilent, 4"
        "$mod SHIFT, 5, movetoworkspacesilent, 5"
        "$mod SHIFT, 6, movetoworkspacesilent, 6"
        "$mod SHIFT, 7, movetoworkspacesilent, 7"
        "$mod SHIFT, 8, movetoworkspacesilent, 8"
        "$mod SHIFT, 9, movetoworkspacesilent, 9"
        "$mod SHIFT, 0, movetoworkspacesilent, 10"
      ];
    };
  };
}
