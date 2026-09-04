{
  darwinSystemModule.homebrew.casks = [
    "ungoogled-chromium"
    # "firefox"
    "vivaldi"
  ];

  nixosHomeModule = { pkgs, ... }: {
    home.packages = [ pkgs.vivaldi ];

    wayland.windowManager.hyprland.settings.bind = [
      "$mod, B, exec, vivaldi"
      "$mod, C, exec, chromium"
    ];
  };
}
