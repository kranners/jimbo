{ pkgs, ... }:
let
  dock-clients = pkgs.writeShellApplication {
    name = "dock-clients";

    runtimeInputs = [
      pkgs.socat
      pkgs.hyprland
      pkgs.jq
    ];

    bashOptions = [ ];

    text = ''
      SOCKET="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"

      # Resolve a window class to an icon name through its desktop entry, so
      # unknown classes fall back to a generic icon instead of rendering as a
      # missing-image placeholder.
      desktop_icon() {
          local class="$1" dir entry
          for dir in ''${XDG_DATA_DIRS//:/ }; do
              for entry in "$dir/applications/$class.desktop" "$dir/applications/''${class,,}.desktop"; do
                  if [[ -f "$entry" ]]; then
                      sed -n 's/^Icon=//p' "$entry" | head -1 | grep . && return
                  fi
              done
          done
          printf 'application-x-executable\n'
      }

      icon_map() {
          local class
          hyprctl clients -j | jq -r '.[].class' | sort -u | while read -r class; do
              [[ -n "$class" ]] || continue
              printf '%s\t%s\n' "$class" "$(desktop_icon "$class")"
          done | jq -Rn '[inputs | split("\t") | { key: .[0], value: .[1] }] | from_entries'
      }

      emit() {
          local workspace active icons
          workspace="$(hyprctl activeworkspace -j | jq '.id')"
          active="$(hyprctl activewindow -j | jq -r '.address // ""')"
          icons="$(icon_map)"

          hyprctl clients -j | jq -c \
              --argjson workspace "$workspace" \
              --arg active "$active" \
              --argjson icons "$icons" \
              '[
                 .[]
                 | select(.workspace.id == $workspace)
                 | {
                     address,
                     title,
                     class,
                     icon: ($icons[.class] // "application-x-executable"),
                     focused: (.address == $active),
                   }
               ]'
      }

      emit

      socat -U - UNIX-CONNECT:"$SOCKET" | while read -r line; do
          case "$line" in
              workspace*|openwindow*|closewindow*|activewindow*|movewindow*|windowtitle*)
                  emit
                  ;;
          esac
      done
    '';
  };

  dock-show = pkgs.writeShellApplication {
    name = "dock-show";

    runtimeInputs = [
      pkgs.hyprland
      pkgs.jq
      pkgs.eww
    ];

    bashOptions = [ ];

    text = ''
      SCREEN="$(hyprctl monitors -j | jq '.[] | select(.focused) | .id')"

      # Already open on another monitor is not an error worth failing on.
      eww open dock --screen "$SCREEN" || true
    '';
  };

in
{
  nixosHomeModule =
    { config, ... }:
    {
      home.packages = [
        dock-clients
        dock-show
      ];

      wayland.windowManager.hyprland = {
        plugins = [ pkgs.hyprlandPlugins.hyprtasking ];

        settings = {
          # The plugin loads from exec-once, after the config is parsed, so the
          # dispatcher does not exist yet when the bind is read.
          bind = [ "$mod, TAB, exec, hyprctl dispatch hyprtasking:toggle all" ];

          "layerrule[dock]" = {
            match.namespace = "dock";
            blur = true;
            ignore_alpha = 0;
          };

          plugin.hyprtasking = {
            layout = "grid";
            gap_size = 10;
            exit_on_hovered = true;

            grid = {
              rows = 3;
              cols = 4;
            };
          };
        };
      };

      systemd.user.services.dock = {
        Unit = {
          Description = "Floating dock hover trigger";
          Wants = [ "eww.service" ];
          PartOf = [ config.wayland.systemd.target ];

          After = [
            config.wayland.systemd.target
            "eww.service"
          ];

          ConditionEnvironment = "WAYLAND_DISPLAY";
        };

        Service = {
          ExecStart = "${pkgs.eww}/bin/eww open dock_trigger";
          ExecStop = "-${pkgs.eww}/bin/eww close dock dock_trigger";
          Type = "oneshot";
          RemainAfterExit = true;
          WorkingDirectory = "${config.xdg.configHome}/eww";
        };

        Install.WantedBy = [ config.wayland.systemd.target ];
      };
    };
}
