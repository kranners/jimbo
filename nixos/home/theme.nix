{ pkgs, ... }: {
  gtk = {
    enable = true;

    iconTheme = {
      package = pkgs.catppuccin-papirus-folders.override {
        flavor = "latte";
        accent = "sky";
      };

      name = "Papirus-Light";
    };

    theme = {
      package = pkgs.catppuccin-gtk.override {
        variant = "latte";
        accents = [ "sky" ];
      };

      name = "Catppuccin-Latte-Standard-Sky-Light";
    };
  };

  # Try to force Qt to behave like GTK so we can just theme that instead
  qt = { enable = true; };

  home.pointerCursor = {
    package = pkgs.catppuccin-cursors.latteDark;
    gtk.enable = true;

    name = "Catppuccin-Latte-Dark-Cursors";
  };
}
