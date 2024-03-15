{pkgs, ...}: {
  gtk = {
    enable = true;

    cursorTheme = {
      package = pkgs.catppuccin-cursors;
      name = "Catppuccin Cursors";
    };

    iconTheme = {
      package = pkgs.papirus-icon-theme;
      name = "Papirus Icon Theme";
    };

    theme = {
      package = pkgs.catppuccin-gtk;
      name = "Catppuccin GTK Theme";
    };
  };
}
