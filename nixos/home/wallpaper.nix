{ config, pkgs, lib, ... }:
let
  wallpaper-dir = "${config.xdg.cacheHome}/wallpapers";

  mkParams = queries: lib.attrsets.foldlAttrs (acc: name: value: "${acc}&${name}=${value}") "" queries;

  wallhaven-queries = {
    categories = "100"; # General | !Anime | !People
    purity = "100"; # SFW | !Sketchy | !NSFW

    atleast = "2560x1440";

    sorting = "hot";
    topRange = "1d";
    order = "desc";

    ai_art_filter = "1";
  };

  download-and-set = pkgs.writeShellApplication {
    name = "download-and-set";

    runtimeInputs = [ pkgs.swaybg pkgs.busybox pkgs.gallery-dl ];

    # You need to start a new swaybg instance before killing the old one,
    # or face the dreaded flicker.
    text = ''
      OLD_PIDS="$(pgrep swaybg || true)"

      gallery-dl \
        --directory="${wallpaper-dir}" \
        --range 1 \
        --no-colors \
        --exec-after 'swaybg -i "{_path}" &' \
        "https://wallhaven.cc/search?${mkParams wallhaven-queries}"

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
