{ config, pkgs, lib, inputs, ... }:
let
  nerd-fonts =
    "Font Awesome 6 Brands:size=14, Font Awesome 6 Free:size=14, Font Awesome 6 Free Solid:size=14";
  jetbrains-mono = "JetBrainsMono Nerd Font Mono:size=14";
in {
  wayland.windowManager.sway.config = {
    terminal = "foot";

    floating = { criteria = [{ app_id = "foot"; }]; };

    window.commands = [{
      criteria = { app_id = "foot"; };
      command = "opacity 0.65";
    }];
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
