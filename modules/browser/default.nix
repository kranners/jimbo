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

  darwinHomeModule = { pkgs, lib, ... }: {
    programs.chromium.package = null;

    home.file.claude-extension-vivaldi-patched = {
      source = import ./claude-vivaldi { inherit pkgs lib; };
      recursive = true;
    };

    launchd.agents.vivaldi-mail-watch = {
      enable = true;

      config = {
        ProgramArguments = [ (lib.getExe (import ./vivaldi-mail-watch.nix { inherit pkgs; })) ];
        StartInterval = 3600;
      };
    };
  };

  nixosHomeModule = { pkgs, ... }: {
    programs.chromium.package = pkgs.ungoogled-chromium;

    wayland.windowManager.hyprland.settings.bind = [
      "$mod, B, exec, chromium"
    ];
  };
}
