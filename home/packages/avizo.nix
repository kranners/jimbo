{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: {
  home.packages = [pkgs.avizo];

  systemd.user.services.avizo = {
    Unit = {
      Description = "MacOS-like volume control hotkeys and notifications";
    };
    Install = {
      WantedBy = ["sway-session.target"];
    };
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
    '';
  };
}
