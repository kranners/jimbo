{ inputs, ... }:
let
  catppuccin-zellij = "${inputs.catppuccin-zellij}/catppuccin.kdl";
in
{
  programs.zellij = {
    enable = true;

    settings = {
      theme = "catppuccin-frappe";
      ui.pane_frames.hide_session_name = true;

      keybinds = {
        # Pretty much anything involving Ctrl
        unbind = [
          "Ctrl s"
          "Ctrl q"
          "Ctrl h"
          "Ctrl d"
          "Ctrl u"
          "Ctrl o"
          "Ctrl n"
          "Ctrl p"
          "Ctrl /"
          "Ctrl ]"
          "Ctrl ["
        ];
      };
    };
  };

  xdg.configFile.catppuccin-zellij = {
    target = "./zellij/themes/catppuccin.kdl";
    source = catppuccin-zellij;
  };
}
