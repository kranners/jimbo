{ pkgs, ... }: {
  darwinSystemModule.homebrew.casks = [
    "ghostty"
  ];

  nixosHomeModule = {
    home.packages = [
      pkgs.ghostty
    ];

    wayland.windowManager.hyprland.settings."$terminal" = "ghostty";
  };

  sharedHomeModule.xdg.configFile.ghostty = {
    target = "./ghostty/config";

    text = ''
      # cyberdream theme for ghostty
      palette = 0=#16181a
      palette = 1=#ff6e5e
      palette = 2=#5eff6c
      palette = 3=#f1ff5e
      palette = 4=#5ea1ff
      palette = 5=#bd5eff
      palette = 6=#5ef1ff
      palette = 7=#ffffff
      palette = 8=#3c4048
      palette = 9=#ff6e5e
      palette = 10=#5eff6c
      palette = 11=#f1ff5e
      palette = 12=#5ea1ff
      palette = 13=#bd5eff
      palette = 14=#5ef1ff
      palette = 15=#ffffff

      background = #16181a
      foreground = #ffffff
      cursor-color = #ffffff
      selection-background = #3c4048
      selection-foreground = #ffffff

      background-opacity = 0.8
      background-blur = 20

      font-family = Iosevka Nerd Font Mono
      font-size = 16

      cursor-style = block
    '';
  };
}
