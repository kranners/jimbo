{
  nixosHomeModule = { config, pkgs, ... }:
    let
      inherit (config.lib.file) mkOutOfStoreSymlink;
      ewwSourceHome = "${config.home.homeDirectory}/workspace/jimbo/modules/eww";

      dashboard = pkgs.writeShellApplication {
        name = "dashboard";

        runtimeInputs = [
          pkgs.socat
          pkgs.hyprland
          pkgs.eww
        ];

        bashOptions = [ ];

        text = ''
          SOCKET="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"
          DASHBOARD_WINDOW="dashboard"

          is_workspace_empty() {
              local ws_id
              ws_id=$(hyprctl activeworkspace -j | jq '.id')
              hyprctl workspaces -j | jq ".[] | select(.id == $ws_id) | .windows" | grep -q '^0$'
          }

          update_dashboard() {
              if is_workspace_empty; then
                  eww open "$DASHBOARD_WINDOW" --screen "$(hyprctl monitors -j | jq '.[] | select(.focused) | .id')"
              else
                  eww close "$DASHBOARD_WINDOW"
              fi
          }

          socat -U - UNIX-CONNECT:"$SOCKET" | while read -r line; do
              case "$line" in
                  workspace*|openwindow*|closewindow*)
                      update_dashboard
                      ;;
              esac
          done
        '';
      };
    in
    {
      # Note to self:
      # DO NOT use programs.eww.enable = true

      xdg.configFile.eww.source = mkOutOfStoreSymlink ewwSourceHome;
      home.packages = [
        pkgs.lm_sensors
        pkgs.eww
        dashboard
      ];

      systemd.user.services.eww = {
        Unit = {
          Description = "eww daemon";
          PartOf = [ config.wayland.systemd.target ];
          After = [ config.wayland.systemd.target ];
          ConditionEnvironment = "WAYLAND_DISPLAY";
        };

        Service = {
          ExecStart = "${pkgs.eww}/bin/eww daemon --no-daemonize";
          Restart = "on-failure";
        };

        Install.WantedBy = [ config.wayland.systemd.target ];
      };

      systemd.user.services.dashboard = {
        Unit = {
          Description = "Auto dashboard opening and closing";
          BindsTo = [ "eww.service" ];
          After = [ config.wayland.systemd.target "eww.service" ];
          ConditionEnvironment = "WAYLAND_DISPLAY";
        };

        Service = {
          ExecStart = "${dashboard}/bin/dashboard";
          Restart = "on-failure";
        };

        Install.WantedBy = [ config.wayland.systemd.target ];
      };
    };
}
