{
  darwinSystemModule.homebrew.casks = [ "plexamp" ];

  nixosHomeModule = { pkgs, ... }: {
    home.packages = [ pkgs.plexamp ];

    wayland.windowManager.hyprland.settings.bind = [
      "$mod, P, exec, plexamp"
    ];
  };
}
