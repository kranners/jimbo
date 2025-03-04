{ pkgs, ... }: {
  nixosSystemModule = {
    programs = {
      thunar.enable = true;
    };

    services = {
      # gnome virtual file service
      # does crap re network drives
      gvfs.enable = true;

      # thumbnailer
      tumbler.enable = true;

      # ui get permission to mount drives as a user
      udisks2.enable = true;
    };

    environment.systemPackages = [ pkgs.file-roller ];
  };

  nixosHomeModule = {
    home.packages = [ pkgs.nautilus ];
    wayland.windowManager.hyprland.settings."$fileManager" = "nautilus";
  };
}
