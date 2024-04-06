{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: {
  home.packages = [pkgs.spotify pkgs.playerctl];

  wayland.windowManager.sway.config.keybindings = {
    "XF86AudioPlay" = "exec playerctl play-pause";
  };
}
