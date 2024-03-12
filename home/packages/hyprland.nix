{
  config,
  pkgs,
  inputs,
  ...
}: {
  wayland.windowManager.hyprland = {
    enable = true;
    xwayland.enable = true;

    settings = {
      # This is an example Hyprland config file.
      #
      # Refer to the wiki for more information.

      #
      # Please note not all available settings / options are set here.
      # For a full list, see the wiki
      #

      # See https://wiki.hyprland.org/Configuring/Monitors/
      monitor = [
        "DP-3, 2560x1440@164, 0x0, 1"
        "DP-1, 1920x1080@144, 2560x0, 1"
      ];

      # See https://wiki.hyprland.org/Configuring/Keywords/ for more

      # Execute your favorite apps at launch
      "exec-once" = [
        pkgs.polkit-kde-agent
        "xrandr --output DP-3 --primary"
        "waybar"
        "swww init"

        # Credit: Pablo Saldaña https://unsplash.com/@pagsa_
        "swww img ${../assets/swww/space.jpg}"
        "dunst"
      ];

      # Source a file (multi-file configs)
      # source = ~/.config/hypr/myColors.conf

      # Set programs that you use
      "$terminal" = "kitty";
      "$fileManager" = "thunar";
      "$menu" = "rofi -show drun";

      "$screenshotRegion" = "grimblast copy area && notify-send 'Region copied to clipboard'";
      "$screenshotWindow" = "grimblast copy active && notify-send 'Window copied to clipboard'";

      "$recordScreen" = "wf-recorder -f \"~/Videos/$(date).mkv\" && notify-send \"Recording saved to ~/Videos/$(date).mkv\"";
      "$recordRegion" = "wf-recorder -g \"$(slurp)\" -f \"~/Videos/$(date).mkv\" && notify-send \"Recording saved to ~/Videos/$(date).mkv\"";

      # Some default env vars.
      env = [
        "XCURSOR_SIZE,24"
        # change to qt6ct if you have that
        "QT_QPA_PLATFORMTHEME,qt5ct"
      ];

      # For all categories, see https://wiki.hyprland.org/Configuring/Variables/
      input = {
        kb_layout = "us";
        # kb_variant =
        # kb_model =
        # kb_options =
        # kb_rules =

        follow_mouse = 1;

        touchpad = {
          natural_scroll = false;
        };

        sensitivity = 0; # -1.0 - 1.0, 0 means no modification.
      };

      general = {
        # See https://wiki.hyprland.org/Configuring/Variables/ for more

        gaps_in = 5;
        gaps_out = 20;
        border_size = 2;
        "col.active_border" = "rgba(33ccffee) rgba(00ff99ee) 45deg";
        "col.inactive_border" = "rgba(595959aa)";

        layout = "dwindle";

        # Please see https://wiki.hyprland.org/Configuring/Tearing/ before you turn this on
        allow_tearing = false;
      };

      decoration = {
        # See https://wiki.hyprland.org/Configuring/Variables/ for more

        rounding = 10;

        blur = {
          enabled = true;
          size = 3;
          passes = 1;

          vibrancy = 0.1696;
        };

        drop_shadow = true;
        shadow_range = 4;
        shadow_render_power = 3;
        "col.shadow" = "rgba(1a1a1aee)";
      };

      animations = {
        enabled = true;

        # Some default animations, see https://wiki.hyprland.org/Configuring/Animations/ for more

        bezier = "myBezier, 0.05, 0.9, 0.1, 1.05";

        animation = [
          "windows, 1, 7, myBezier"
          "windowsOut, 1, 7, default, popin 80%"
          "border, 1, 10, default"
          "borderangle, 1, 8, default"
          "fade, 1, 7, default"
          "workspaces, 1, 6, default"
        ];
      };

      dwindle = {
        # See https://wiki.hyprland.org/Configuring/Dwindle-Layout/ for more
        pseudotile = false; # master switch for pseudotiling. Enabling is bound to mainMod + P in the keybinds section below
        preserve_split = true; # you probably want this
      };

      master = {
        # See https://wiki.hyprland.org/Configuring/Master-Layout/ for more
        new_is_master = true;
      };

      gestures = {
        # See https://wiki.hyprland.org/Configuring/Variables/ for more
        workspace_swipe = false;
      };

      misc = {
        # See https://wiki.hyprland.org/Configuring/Variables/ for more
        # force_default_wallpaper = -1; # Set to 0 or 1 to disable the anime mascot wallpapers
        disable_hyprland_logo = true;
      };

      # Example per-device config
      # See https://wiki.hyprland.org/Configuring/Keywords/#per-device-input-configs for more

      # Example windowrule v1
      # windowrule = float, ^(kitty)$
      # Example windowrule v2
      # windowrulev2 = float,class:^(kitty)$,title:^(kitty)$
      # See https://wiki.hyprland.org/Configuring/Window-Rules/ for more
      windowrulev2 = "suppressevent maximize, class:.*"; # You'll probably like this.

      # See https://wiki.hyprland.org/Configuring/Keywords/ for more
      "$mainMod" = "SUPER";

      # Example binds, see https://wiki.hyprland.org/Configuring/Binds/ for more
      bind = [
        # Normal human bindings
        "ALT, 4, killactive,"
        "ALT SHIFT, Tab, cyclenext, prev"

        "$mainMod, Q, exec, $terminal"
        "$mainMod, C, killactive,"
        "$mainMod, M, exit,"
        "$mainMod, E, exec, $fileManager"
        "$mainMod, SPACE, exec, $menu"
        "$mainMod, P, pseudo," # dwindle
        "$mainMod, J, togglesplit," # dwindle

        # Move focus with mainMod + arrow keys
        "$mainMod, left, movefocus, l"
        "$mainMod, right, movefocus, r"
        "$mainMod, up, movefocus, u"
        "$mainMod, down, movefocus, d"

        # Switch workspaces with mainMod + [0-9]
        "$mainMod, 1, workspace, 1"
        "$mainMod, 2, workspace, 2"
        "$mainMod, 3, workspace, 3"
        "$mainMod, 4, workspace, 4"
        "$mainMod, 5, workspace, 5"
        "$mainMod, 6, workspace, 6"
        "$mainMod, 7, workspace, 7"
        "$mainMod, 8, workspace, 8"
        "$mainMod, 9, workspace, 9"
        "$mainMod, 0, workspace, 10"

        # Move active window to a workspace with mainMod + SHIFT + [0-9]
        "$mainMod CTRL, 1, movetoworkspace, 1"
        "$mainMod CTRL, 2, movetoworkspace, 2"
        "$mainMod CTRL, 3, movetoworkspace, 3"
        "$mainMod CTRL, 4, movetoworkspace, 4"
        "$mainMod CTRL, 5, movetoworkspace, 5"
        "$mainMod CTRL, 6, movetoworkspace, 6"
        "$mainMod CTRL, 7, movetoworkspace, 7"
        "$mainMod CTRL, 8, movetoworkspace, 8"
        "$mainMod CTRL, 9, movetoworkspace, 9"
        "$mainMod CTRL, 0, movetoworkspace, 10"

        # Screenshot utility bindings
        "$mainMod SHIFT, S, exec, $screenshotRegion"
        "$mainMod SHIFT, 4, exec, $screenshotRegion"
        "$mainMod SHIFT, 3, exec, $screenshotWindow"

        # Screen record bindings
        "$mainMod ALT, S, exec, $recordRegion"
        "$mainMod ALT, 4, exec, $recordRegion"
        "$mainMod ALT, 3, exec, $recordScreen"

        # Manage clipboard history
        "SUPER, V, exec, cliphist list | rofi -dmenu | cliphist decode | wl-copy"

        # Scroll through existing workspaces with mainMod + scroll
        "$mainMod, mouse_down, workspace, e+1"
        "$mainMod, mouse_up, workspace, e-1"
      ];

      # Move/resize windows with mainMod + LMB/RMB and dragging
      bindm = [
        "$mainMod, mouse:272, movewindow"
        "$mainMod, mouse:273, resizewindow"
      ];
    };
  };
}
