{ pkgs, lib, ... }: let
  inherit (pkgs.hostPlatform) isLinux;
in {
  programs.alacritty = {
    enable = true;

    # https://alacritty.org/config-alacritty.html
    settings = {
      window = {
        padding = { x = 15; y = 15; };
        decorations = "Full";
        opacity = 0.80;
        resize_increments = true;
        option_as_alt = "OnlyLeft";
      };

      colors.transparent_background_colors = true;

      font = {
        size = if isLinux then 12.0 else 16.0;
        normal = { family = "Iosevka Nerd Font Mono"; style = "Regular"; };
        bold = { family = "Iosevka Nerd Font Mono"; style = "Regular"; };
      };
    };
  };

  wayland.windowManager.sway.config = lib.mkIf isLinux {
    terminal = "alacritty";
  };
}
