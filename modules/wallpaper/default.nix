{ pkgs, ... }:
let
  wallpaperDirectory = "Pictures/wallpapers";
  keptWallpapers = 60;

  searchParameters = [
    "sorting=random"
    "atleast=2560x1440"
    "ratios=16x9"
    "categories=100"
    "purity=100"
  ];

  fetch-wallpapers = pkgs.writeShellApplication {
    name = "fetch-wallpapers";

    runtimeInputs = [ pkgs.curl pkgs.jq pkgs.coreutils pkgs.findutils pkgs.systemd ];

    text = ''
      directory="$HOME/${wallpaperDirectory}"
      mkdir -p "$directory"

      curl -fsS "https://wallhaven.cc/api/v1/search?${builtins.concatStringsSep "&" searchParameters}" \
        | jq -r '.data[].path' \
        | while read -r url; do
            destination="$directory/$(basename "$url")"
            [ -e "$destination" ] || curl -fsS -o "$destination" "$url"
          done

      find "$directory" -maxdepth 1 -type f -printf '%T@ %p\0' \
        | sort -zrn \
        | tail -zn "+$((${toString keptWallpapers} + 1))" \
        | cut -zd' ' -f2- \
        | xargs -0r rm --

      # wpaperd scans its directory once at startup and gives up if it was
      # empty, so it needs a restart after the directory is first filled.
      systemctl --user try-restart wpaperd.service
    '';
  };
in
{
  nixosHomeModule = { config, ... }: {
    home.packages = [ fetch-wallpapers ];

    services.wpaperd = {
      enable = true;
      settings.default = {
        path = "${config.home.homeDirectory}/${wallpaperDirectory}";
        sorting = "random";
        duration = "30m";
      };
    };

    systemd.user.timers.wallpapers = {
      Unit.Description = "wallhaven wallpaper fetcher";
      Install.WantedBy = [ "timers.target" ];

      Timer = {
        OnBootSec = "2m";
        OnUnitActiveSec = "1d";
        Persistent = true;
        Unit = "wallpapers.service";
      };
    };

    systemd.user.services.wallpapers = {
      Unit.Description = "wallhaven wallpaper fetcher";

      Service = {
        ExecStart = "${fetch-wallpapers}/bin/fetch-wallpapers";
        Type = "oneshot";
      };
    };
  };
}
