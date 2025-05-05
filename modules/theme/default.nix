{ pkgs, ... }: {
  nixosHomeModule = {
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
    };

    # Try to force Qt to behave like GTK so we can just theme that instead
    qt = { enable = true; };

    home.pointerCursor = {
      package = pkgs.hackneyed;
      gtk.enable = true;
      name = "Hackneyed";
    };
  };
}
