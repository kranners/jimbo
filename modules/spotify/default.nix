{
  darwinSystemModule.homebrew.casks = [ "spotify" ];

  nixosHomeModule = { pkgs, ... }: {
    home.packages = [ pkgs.spotify ];

    wayland.windowManager.hyprland.settings.bind = [
      "$mod, Y, exec, spotify"
    ];
  };
}
