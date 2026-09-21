{ pkgs, ... }: {
  nixosHomeModule = { config, ... }: {
    gtk = {
      enable = true;

      theme = {
        package = pkgs.gnome-themes-extra;
        name = "Adwaita";
      };

      iconTheme = {
        name = "Papirus";
        package = pkgs.papirus-icon-theme;
      };

      gtk4.theme = config.gtk.theme;
    };

    # Try to force Qt to behave like GTK so we can just theme that instead
    qt = { enable = true; };

    home.pointerCursor = {
      enable = true;
      package = pkgs.hackneyed;
      gtk.enable = true;
      name = "Hackneyed";
    };
  };
}
