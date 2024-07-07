{ pkgs, ... }:
let
  download-and-set = pkgs.writeShellApplication {
    name = "download-and-set";

    # This doesn't work with the wget from busybox OR toybox
    runtimeInputs = [ pkgs.swaybg pkgs.wget pkgs.procps ];

    # You need to start a new swaybg instance before killing the old one,
    # or face the dreaded flicker.
    text = ''
      OLD_PIDS="$(pgrep swaybg || true)"

      wget -O /tmp/wallpaper.jpg "https://picsum.photos/2560/1440?random"

      swaybg -i /tmp/wallpaper.jpg &

      for PID in $OLD_PIDS; do
        [[ -n "$PID" ]] && kill "$PID"
      done
    '';
  };
in
{
  home.packages = [ download-and-set ];

  systemd.user.services = {
    wallpaper = {
      Unit = {
        Description = "download-and-set script";
        After = [ "graphical-session-pre.target" ];
        PartOf = [ "graphical-session.target" ];
      };

      Install.WantedBy = [ "sway-session.target" ];

      Service = {
        ExecStart = "${download-and-set}/bin/download-and-set";
        RemainAfterExit = true;
      };
    };
  };
}
