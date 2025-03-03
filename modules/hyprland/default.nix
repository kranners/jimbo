{ pkgs, ... }:
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
in
{
  nixosHomeModule.home.packages = [
    exit-if-all-closed
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

    plugins = [
      pkgs.hyprlandPlugins.hyprspace
      pkgs.hyprlandPlugins.hyprsplit
    ];

    settings = {
      "$mod" = "SUPER";
      "$fileManager" = "nemo";
      "$terminal" = "alacritty";

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

      plugin = {
        hyprbars = {
          bar_height = 30;
          bar_precedence_over_border = true;
          bar_buttons_alignment = "left";

          # order is right-to-left
          hyprbars-button = [
            # close
            "rgb(FF605C), 15, , hyprctl dispatch killactive"
            # maximize
            "rgb(00CA4E), 15, , hyprctl dispatch fullscreen 1"
          ];
        };
      };

      exec-once = [
        "${pkgs.hyprsunset} --temperature 5700"
      ];

      bindm = [
        "$mod, mouse:272, movewindow"
        "$mod, mouse:273, resizewindow"
      ];

      bind = [
        "$mod, SPACE, exec, $launcher"
        "$mod, TAB, overview:toggle, all"

        "$mod, RETURN, exec, $terminal"
        "$mod, E, exec, $fileManager"

        "$mod SHIFT, S, exec, grim -g \"$(slurp -d)\" - | wl-copy && notify-send 'Copied to clipboard'"

        "$mod SHIFT, Q, exec, exit-if-all-closed"

        "$mod, F, fullscreen"

        "$mod, H, movefocus, l"
        "$mod, J, movefocus, d"
        "$mod, K, movefocus, u"
        "$mod, L, movefocus, r"
        "$mod SHIFT, H, movewindow, l"
        "$mod SHIFT, J, movewindow, d"
        "$mod SHIFT, K, movewindow, u"
        "$mod SHIFT, L, movewindow, r"

        "$mod, 1, split:workspace, 1"
        "$mod, 2, split:workspace, 2"
        "$mod, 3, split:workspace, 3"
        "$mod, 4, split:workspace, 4"
        "$mod, 5, split:workspace, 5"
        "$mod, 6, split:workspace, 6"
        "$mod, 7, split:workspace, 7"
        "$mod, 8, split:workspace, 8"
        "$mod, 9, split:workspace, 9"
        "$mod, 0, split:workspace, 10"

        "$mod SHIFT, 1, split:movetoworkspacesilent, 1"
        "$mod SHIFT, 2, split:movetoworkspacesilent, 2"
        "$mod SHIFT, 3, split:movetoworkspacesilent, 3"
        "$mod SHIFT, 4, split:movetoworkspacesilent, 4"
        "$mod SHIFT, 5, split:movetoworkspacesilent, 5"
        "$mod SHIFT, 6, split:movetoworkspacesilent, 6"
        "$mod SHIFT, 7, split:movetoworkspacesilent, 7"
        "$mod SHIFT, 8, split:movetoworkspacesilent, 8"
        "$mod SHIFT, 9, split:movetoworkspacesilent, 9"
        "$mod SHIFT, 0, split:movetoworkspacesilent, 10"
      ];
    };
  };
}
