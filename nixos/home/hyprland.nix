{ inputs, pkgs, ... }:
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
    pkgs.ulauncher
  ];

  wayland.windowManager.hyprland = {
    enable = true;

    settings = {
      "$mod" = "SUPER";
      "$terminal" = "alacritty";
      "$fileManager" = "nemo";
      "$menu" = "ulauncher";

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

        "$mod SHIFT, 1, movetoworkspace, 1"
        "$mod SHIFT, 2, movetoworkspace, 2"
        "$mod SHIFT, 3, movetoworkspace, 3"
        "$mod SHIFT, 4, movetoworkspace, 4"
        "$mod SHIFT, 5, movetoworkspace, 5"
        "$mod SHIFT, 6, movetoworkspace, 6"
        "$mod SHIFT, 7, movetoworkspace, 7"
        "$mod SHIFT, 8, movetoworkspace, 8"
        "$mod SHIFT, 9, movetoworkspace, 9"
        "$mod SHIFT, 0, movetoworkspace, 10"
      ];
    };
  };
}
