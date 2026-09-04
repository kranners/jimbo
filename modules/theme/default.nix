{ lib, ... }:
let
  inherit (lib) mkOption types;
in
{
  options = {
    theme.colors = mkOption {
      description = "Palette shared by themed components.";
      type = types.attrsOf types.str;

      default = {
        bg = "#11111B";
        bg-light = "#1E1E2E";
        border = "#313244";
        fg = "#CDD6F4";
        accent = "#B4BEFE";
        inactive = "#45475A";
      };
    };
  };

  config = {
    # Required to prevent Home Manager crashing
    # https://github.com/nix-community/home-manager/issues/3113
    nixosSystemModule.programs.dconf.enable = true;

    nixosHomeModule = { pkgs, ... }: {
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

      home.sessionVariables = {
        # Force Qt applications to run through the Wayland platform plugin
        QT_QPA_PLATFORM = "wayland";
      };
    };
  };
}
