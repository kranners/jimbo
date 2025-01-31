{ pkgs, ... }:
let
  screenshot-region = pkgs.writeShellApplication {
    name = "screenshot-region";

    runtimeInputs = [
      pkgs.grim
      pkgs.slurp
      pkgs.wl-clipboard
    ];

    text = ''
      grim -g "$(slurp -d)" - | wl-copy && notify-send "Copied region to clipboard"
    '';
  };
in
{
  home.packages = [
    screenshot-region
    pkgs.nwg-dock-hyprland
  ];

  wayland.windowManager.hyprland = {
    enable = true;

    plugins = [
      pkgs.hyprlandPlugins.hyprspace
      pkgs.hyprlandPlugins.hyprsplit
      pkgs.hyprlandPlugins.hyprbars
    ];

    settings = {
      "$mod" = "SUPER";
      "$fileManager" = "nemo";
      "$terminal" = "alacritty";

      plugin = {
        hyprbars = {
          bar_height = 20;
          bar_precedence_over_border = true;

          # order is right-to-left
          hyprbars-button = [
            # close
            "rgb(FF605C), 10, , hyprctl dispatch killactive"
            # maximize
            "rgb(00CA4E), 10, , hyprctl dispatch fullscreen 1"
          ];
        };
      };

      exec-once = [
        "uwsm app -- ${pkgs.nwg-dock-hyprland}/bin/nwg-dock-hyprland -d"
      ];

      windowrule = [
        "noblur, ulauncher"
        "opaque, ulauncher"
        "size 100% 100%, ulauncher"
        "noborder, ulauncher"
        "noanim, ulauncher"
        "float, ulauncher"
        "pin, ulauncher"
      ];

      bindm = [
        "$mod, mouse:272, movewindow"
        "$mod, mouse:273, resizewindow"
      ];

      bind = [
        "$mod, SPACE, exec, $menu"
        "$mod, TAB, overview:toggle, all"

        "$mod, RETURN, exec, $terminal"
        "$mod, E, exec, $fileManager"

        "$mod SHIFT, S, exec, screenshot-region"

        "$mod SHIFT, Q, killactive"

        "$mod, F, togglefloating"

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
