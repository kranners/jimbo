{ pkgs, config, ... }:
let
  TEMP_WALLPAPER_PATH = "/tmp/wallpaper.jpg";

  set-wallpaper = pkgs.writeShellApplication {
    name = "set-wallpaper";

    # This doesn't work with the wget from busybox OR toybox
    runtimeInputs = [ pkgs.swaybg pkgs.wget pkgs.procps ];

    text = ''
      OLD_PIDS="$(pgrep swaybg || true)"

      swaybg -i ${TEMP_WALLPAPER_PATH} &

      for PID in $OLD_PIDS; do
        [[ -n "$PID" ]] && kill "$PID"
      done
    '';
  };

  download-and-set = pkgs.writeShellApplication {
    name = "download-and-set";

    # This doesn't work with the wget from busybox OR toybox
    runtimeInputs = [ pkgs.swaybg pkgs.wget pkgs.procps set-wallpaper ];

    text = ''
      # Set the wallpaper first, one should already exist
      set-wallpaper

      wget -O ${TEMP_WALLPAPER_PATH} "https://picsum.photos/2560/1440?random"

      set-wallpaper
    '';
  };
in
{
  home.packages = [ download-and-set set-wallpaper ];

  systemd.user.services = {
    wallpaper = {
      Unit = {
        Description = "download-and-set script";
        After = [ "graphical-session-pre.target" ];
        PartOf = [ "graphical-session.target" ];
      };

      Install.WantedBy = [ config.wayland.systemd.target ];

      Service = {
        ExecStart = "${download-and-set}/bin/download-and-set";
        RemainAfterExit = true;
      };
    };
  };
}
