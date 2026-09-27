top: {
  nixosHomeModule =
    {
      lib,
      config,
      pkgs,
      ...
    }:
    let
      inherit (config.lib.file) mkOutOfStoreSymlink;
      ewwSourceHome = "${config.home.homeDirectory}/${top.config.repoPath}/modules/eww";

      llmStatus = pkgs.writeShellApplication {
        name = "llm-status";

        runtimeInputs = [
          pkgs.curl
          pkgs.jq
          pkgs.systemd
        ];

        text = ''
          root="${lib.removeSuffix "/v1" top.config.llm.baseUrl}"

          gateway_state=$(systemctl --user is-active openclaw.service || true)
          server_state=$(systemctl --user is-active llama-server.service || true)

          properties=$(curl --silent --fail --max-time 2 "$root/props" || true)
          metrics=$(curl --silent --fail --max-time 2 "$root/metrics" | grep --invert-match '^#' || true)

          metric() {
            awk -v name="$1" '$1 == name { value = $2 } END { print value + 0 }' <<< "$metrics"
          }

          if [ -z "$properties" ]; then
            jq --null-input --compact-output \
              --arg gateway "$gateway_state" \
              --arg server "$server_state" \
              '{
                online: false,
                model: "",
                slots_total: 0,
                requests_processing: 0,
                requests_deferred: 0,
                prompt_tokens_per_second: 0,
                generated_tokens_per_second: 0,
                gateway_state: $gateway,
                server_state: $server
              }'
            exit 0
          fi

          jq --compact-output \
            --arg gateway "$gateway_state" \
            --arg server "$server_state" \
            --argjson processing "$(metric llamacpp:requests_processing)" \
            --argjson deferred "$(metric llamacpp:requests_deferred)" \
            --argjson promptTokens "$(metric llamacpp:prompt_tokens_total)" \
            --argjson promptSeconds "$(metric llamacpp:prompt_seconds_total)" \
            --argjson generatedTokens "$(metric llamacpp:tokens_predicted_total)" \
            --argjson generatedSeconds "$(metric llamacpp:tokens_predicted_seconds_total)" \
            '{
              online: true,
              model: .model_alias,
              slots_total: .total_slots,
              requests_processing: $processing,
              requests_deferred: $deferred,
              prompt_tokens_per_second:
                (if $promptSeconds > 0 then $promptTokens / $promptSeconds else 0 end),
              generated_tokens_per_second:
                (if $generatedSeconds > 0 then $generatedTokens / $generatedSeconds else 0 end),
              gateway_state: $gateway,
              server_state: $server
            }' <<< "$properties"
        '';
      };

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
          # A dashboard opened by keybind has to survive the workspace watcher
          # below, which would otherwise close it on the very next window event.
          PIN="$XDG_RUNTIME_DIR/dashboard-pinned"

          open_dashboard() {
              eww --no-daemonize open "$DASHBOARD_WINDOW" --screen "$(hyprctl monitors -j | jq '.[] | select(.focused) | .id')"
          }

          is_workspace_empty() {
              local ws_id
              ws_id=$(hyprctl activeworkspace -j | jq '.id')
              hyprctl workspaces -j | jq ".[] | select(.id == $ws_id) | .windows" | grep -q '^0$'
          }

          update_dashboard() {
              [ -e "$PIN" ] && return

              if is_workspace_empty; then
                  open_dashboard
              else
                  eww --no-daemonize close "$DASHBOARD_WINDOW"
              fi
          }

          case "''${1:-watch}" in
              toggle)
                  if [ -e "$PIN" ]; then
                      rm -f "$PIN"
                      update_dashboard
                  else
                      touch "$PIN"
                      [ -n "''${2:-}" ] && eww --no-daemonize update quick_tab="$2"
                      open_dashboard
                  fi
                  exit 0
                  ;;
              close)
                  rm -f "$PIN"
                  eww --no-daemonize close-all
                  exit 0
                  ;;
          esac

          rm -f "$PIN"

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
        # weather.py, network_speed.py and set_output_device.py are run straight
        # off PATH by eww, so python3 has to be in the profile.
        pkgs.python3
        llmStatus
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
          Wants = [ "eww.service" ];
          After = [
            config.wayland.systemd.target
            "eww.service"
          ];
          ConditionEnvironment = "WAYLAND_DISPLAY";
        };

        Service = {
          ExecStart = "${dashboard}/bin/dashboard";
          Restart = "on-failure";
          WorkingDirectory = "${config.xdg.configHome}/eww";
        };

        Install.WantedBy = [ config.wayland.systemd.target ];
      };

      systemd.user.timers.weather = {
        Unit.Description = "weather refresher";
        Install.WantedBy = [ "timers.target" ];

        Timer = {
          OnBootSec = "5m";
          OnUnitActiveSec = "15m";
          Unit = "weather.service";
        };
      };

      systemd.user.services.weather = {
        Unit.Description = "weather refresher";
        Install.WantedBy = [ config.wayland.systemd.target ];

        Service = {
          ExecStart = "${pkgs.python3}/bin/python3 ${toString ./scripts/weather.py}";
          Type = "oneshot";
        };
      };
    };
}
