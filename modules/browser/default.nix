{
  darwinSystemModule.homebrew.casks = [
    "ungoogled-chromium"
    # "firefox"
  ];

  sharedHomeModule = { pkgs, ... }: {
    programs.chromium = {
      enable = true;
      extensions = import ./extensions.nix { inherit pkgs; };
    };
  };

  darwinHomeModule.programs.chromium.package = null;

  nixosHomeModule = { pkgs, ... }: {
    programs.chromium.package = pkgs.ungoogled-chromium;

    wayland.windowManager.hyprland.settings.bind = [
      "$mod, B, exec, chromium"
    ];
  };
}
