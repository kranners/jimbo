{ config
, pkgs
, lib
, inputs
, ...
}:
let
  spotify-play-pause = pkgs.writeShellApplication {
    name = "spotify-play-pause";

    runtimeInputs = [ pkgs.avizo pkgs.playerctl ];

    text = ''
      STATUS="$(playerctl -p spotify status)"

      if [ "$STATUS" = Playing ]; then
        playerctl -p spotify pause
        avizo-client --image-path=${../../assets/media-pause.png}
        exit 0
      fi

      playerctl -p spotify play
      avizo-client --image-path=${../../assets/media-play.png}
    '';
  };
in
{
  home.packages = [ pkgs.avizo pkgs.playerctl spotify-play-pause ];

  systemd.user.services.avizo = {
    Unit = {
      Description = "MacOS-like volume control hotkeys and notifications";
    };
    Install = { WantedBy = [ "sway-session.target" ]; };
    Service = {
      ExecStart = "${pkgs.avizo}/bin/avizo-service";
      Restart = "always";
      RestartSec = "3";
    };
  };

  wayland.windowManager.sway.config = {
    startup = [
      {
        command = "systemctl --user restart avizo";
        always = true;
      }
    ];

    keybindings = {
      "XF86AudioRaiseVolume" = "exec volumectl -u up";
      "XF86AudioLowerVolume" = "exec volumectl -u down";
      "XF86AudioMute" = "exec volumectl toggle-mute";
      "XF86AudioMicMute" = "exec volumectl -m toggle-mute";

      "XF86AudioPlay" = "exec spotify-play-pause";

      "XF86MonBrightnessUp" = "exec lightctl up";
      "XF86MonBrightnessDown" = "exec lightctl down";
    };
  };

  # Config reference:
  # https://github.com/misterdanb/avizo/blob/master/config.ini
  xdg.configFile.avizo = {
    target = "./avizo/config.ini";

    text = ''
      [default]
      # Show the notification for only 1s, instead of 5s
      time = 1.0

      # Make the notification appear in the middle of the screen, instead of slightly down
      y-offset = 0.5
    '';
  };
}
