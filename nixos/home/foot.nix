{ config
, pkgs
, lib
, inputs
, ...
}:
let
  nerd-fonts = "Font Awesome 6 Brands:size=10, Font Awesome 6 Free:size=10, Font Awesome 6 Free Solid:size=10";
  jetbrains-mono = "JetBrainsMono Nerd Font Mono:size=10";
in
{
  wayland.windowManager.sway.config = {
    terminal = "foot";

    # You may get your day in the sun yet, floating foot
    # floating = { criteria = [{ app_id = "foot"; }]; };

    # Also not you, opacity :(
    # window.commands = [{
    #   criteria = { app_id = "foot"; };
    #   command = "opacity 0.65";
    # }];
  };

  programs.foot = {
    enable = true;
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
}
