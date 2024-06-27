{ pkgs, ... }: {
  programs.alacritty = {
    enable = true;

    # https://alacritty.org/config-alacritty.html
    settings = {
      import = [ "${pkgs.alacritty-theme}/one_dark.toml" ];

      window = {
        padding = { x = 15; y = 15; };
        decorations = "Buttonless";
        opacity = 0.80;
        resize_increments = true;
        option_as_alt = "OnlyLeft";
      };

      colors.transparent_background_colors = true;

      font = {
        size = 16.0;
        normal = { family = "JetBrainsMono Nerd Font Mono"; style = "Regular"; };
      };
    };
  };
}
