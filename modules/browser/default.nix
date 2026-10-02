{
  darwinSystemModule.homebrew.casks = [
    "ungoogled-chromium"
    # "firefox"
  ];

  darwinHomeModule = { pkgs, lib, ... }: {
    home.file.claude-extension-vivaldi-patched = {
      source = import ./claude-vivaldi { inherit pkgs lib; };
      recursive = true;
    };
  };

  nixosHomeModule = { pkgs, ... }: {
    programs.chromium = {
      enable = true;
      package = pkgs.ungoogled-chromium;
      extensions = import ./extensions.nix { inherit pkgs; };
    };

    wayland.windowManager.hyprland.settings.bind = [
      "$mod, B, exec, chromium"
    ];
  };
}
