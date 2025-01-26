{ config
, pkgs
, lib
, inputs
, ...
}:
let
  play-pause = pkgs.writeShellApplication {
    name = "play-pause";

    runtimeInputs = [ pkgs.avizo pkgs.playerctl ];

    text = ''
      FALLBACK_PLAYER="spotify"
      PLAYER_COUNT="$(playerctl --list-all | grep -cE 'spotify|Plexamp')"

      if [ "$PLAYER_COUNT" -gt 1 ]; then
        notify-send "Both Spotify and Plexamp open! Unsure which to pick, falling back to $FALLBACK_PLAYER"
        PLAYER="$FALLBACK_PLAYER"
      elif [ "$PLAYER_COUNT" -eq 1 ]; then
        PLAYER="$(playerctl --list-all | grep -E 'spotify|Plexamp')"
      else
        notify-send "Not currently playing anything 🙃"
        exit 0
      fi

      STATUS="$(playerctl -p "$PLAYER" status)"

      if [ "$STATUS" = Playing ]; then
        playerctl -p "$PLAYER" pause
        avizo-client --image-path=${../../assets/media-pause.png}
        exit 0
      fi

      playerctl -p "$PLAYER" play
      avizo-client --image-path=${../../assets/media-play.png}
    '';
  };
in
{
  home.packages = [ pkgs.avizo pkgs.playerctl play-pause ];

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

  wayland.windowManager.hyprland.settings = {
    exec-once = "uwsm app -- systemctl --user restart avizo";

    bindl = [
      ",XF86AudioRaiseVolume, exec, volumectl -u up"
      ",XF86AudioLowerVolume, exec, volumectl -u down"
      ",XF86AudioMute, exec, volumectl toggle-mute"
      ",XF86AudioMicMute, exec, volumectl -m toggle-mute"
      ",XF86AudioPlay, exec, play-pause"
      ",XF86MonBrightnessUp, exec, lightctl up"
      ",XF86MonBrightnessDown, exec, lightctl down"
    ];
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
