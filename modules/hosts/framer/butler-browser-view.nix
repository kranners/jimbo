{
  lib,
  pkgs,
  host,
  ...
}:
let
  domain = "browser.spike.cute.engineer";

  butler-browser-view = pkgs.writeShellApplication {
    name = "butler-browser-view";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.curl
      pkgs.ungoogled-chromium
    ];
    text = ''
      export XDG_RUNTIME_DIR=/run/user/$UID
      export WAYLAND_DISPLAY=wayland-0
      viewer=""
      trap '[ -z "$viewer" ] || kill "$viewer"' EXIT

      while true; do
        if [ "$(curl -fsS --max-time 3 https://${domain}/active 2> /dev/null)" = 1 ]; then
          if [ -z "$viewer" ] || ! kill -0 "$viewer" 2> /dev/null; then
            chromium \
              --kiosk \
              --ozone-platform=wayland \
              --user-data-dir="$RUNTIME_DIRECTORY/profile" \
              --no-first-run \
              --noerrdialogs \
              --disable-session-crashed-bubble \
              --disable-infobars \
              "https://${domain}/vnc.html?autoconnect=1&reconnect=1&resize=scale&view_only=1" &
            viewer=$!
          fi
        elif [ -n "$viewer" ]; then
          kill "$viewer" 2> /dev/null || true
          wait "$viewer" || true
          viewer=""
        fi
        sleep 2
      done
    '';
  };
in
{
  networking.hosts."10.100.0.1" = [ domain ];

  systemd.services.butler-browser-view = {
    description = "Show butler's browser on the panel while butler drives it";
    wantedBy = [ "graphical.target" ];
    after = [ "cage-tty1.service" ];
    serviceConfig = {
      User = host.username;
      RuntimeDirectory = "butler-browser-view";
      ExecStart = lib.getExe butler-browser-view;
      Restart = "always";
      RestartSec = 5;
    };
  };
}
