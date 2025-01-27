{ pkgs, config, ... }:
let
  pictures-dir = config.xdg.userDirs.pictures;

  swww-randomize = pkgs.writeShellApplication {
    name = "swww-randomize";

    runtimeInputs = [ pkgs.swww ];

    text = ''
      # Edit below to control the images transition
      export SWWW_TRANSITION_FPS=60
      export SWWW_TRANSITION_STEP=2

      # This controls (in seconds) when to switch to the next image
      INTERVAL=300

      while true; do
        find "${pictures-dir}" -type f \
          | while read -r img; do
            echo "$((RANDOM % 1000)):$img"
          done \
          | sort -n | cut -d':' -f2- \
          | while read -r img; do
            swww img "$img"
            sleep $INTERVAL
          done
      done
    '';
  };
in
{
  home.packages = [ pkgs.swww swww-randomize ];

  systemd.user.services.swww = {
    Unit = {
      Description = "SWWW daemon";
      ConditionEnvironment = "WAYLAND_DISPLAY";
      PartOf = [ "graphical-session.target" ];
    };

    Service = {
      ExecStart = "${pkgs.swww}/bin/swww-daemon";
      Restart = "on-failure";
    };

    Install.WantedBy = [ "sway-session.target" ];
  };

  systemd.user.services.swww-randomize = {
    Unit = {
      Description = "SWWW wallpaper randomizing script";
      ConditionEnvironment = "WAYLAND_DISPLAY";
      PartOf = [ "graphical-session.target" ];
    };

    Service = {
      ExecStart = "${swww-randomize}/bin/sww-randomize";
      Restart = "on-failure";
    };

    Install.WantedBy = [ "sway-session.target" ];
  };
}
