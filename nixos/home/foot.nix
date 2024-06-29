{ config, lib, ... }:
let
  nerd-fonts = "Font Awesome 6 Brands:size=14, Font Awesome 6 Free:size=14, Font Awesome 6 Free Solid:size=14";
  jetbrains-mono = "JetBrainsMono Nerd Font Mono:size=14";
in
{
  programs.foot = {
    enable = false;
    settings = {
      main = {
        term = "xterm-256color";
        dpi-aware = "yes";

        initial-window-size-pixels = "1500x900";

        font = "${jetbrains-mono}, ${nerd-fonts}";
        font-bold = "${jetbrains-mono}:style=Bold, ${nerd-fonts}";
        font-italic = "${jetbrains-mono}:style=Italic, ${nerd-fonts}";
      };
    };
  };

  wayland.windowManager.sway.config = lib.mkIf config.programs.foot.enable {
    terminal = "foot";
  };
}
