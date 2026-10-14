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

    launchd.agents.vivaldi-mail-watch = {
      enable = true;

      config = {
        ProgramArguments = [ (lib.getExe (import ./vivaldi-mail-watch.nix { inherit pkgs; })) ];
        StartInterval = 3600;
      };
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
