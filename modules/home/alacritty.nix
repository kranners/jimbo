{
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
        normal = { family = "Iosevka Nerd Font Mono"; style = "Regular"; };
        bold = { family = "Iosevka Nerd Font Mono"; style = "Regular"; };
      };
    };
  };
}
