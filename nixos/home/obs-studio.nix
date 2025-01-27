{ config, pkgs, ... }:
let
  modifier = config.wayland.windowManager.sway.config.modifier;

  save-replay = pkgs.writeShellApplication {
    name = "save-replay";

    runtimeInputs = [ pkgs.obs-cmd ];

    text = ''
      obs-cmd replay save && notify-send "Replay saved to ~/replays/Replay $(date '+%Y-%m-%d %H-%M-%S').mp4"
    '';
  };
in
{
  programs.obs-studio.enable = true;
  home.packages = [ save-replay ];

  systemd.user.services.obs = {
    Unit = {
      Description = "OBS Studio, mainly for screen recordings and replays";
    };
    Install = { WantedBy = [ config.wayland.systemd.target ]; };
    Service = {
      ExecStart = "${pkgs.obs-studio}/bin/obs --startreplaybuffer --minimize-to-tray --disable-shutdown-check";
      Restart = "always";
      RestartSec = "3";
    };
  };

  wayland.windowManager.sway.config.keybindings = {
    "${modifier}+Shift+r" = "exec save-replay";
  };
}
