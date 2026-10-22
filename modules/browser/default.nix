{ pkgs, host, ... }:
let
  extensions = import ./extensions.nix { inherit pkgs; };
in
{
  # Fetching every pin in CI pushes it to the kranners cache, which keeps
  # serving it after the Chrome Web Store has moved on to a newer release.
  checks.${host.system}.browser-extensions = pkgs.linkFarmFromDrvs "browser-extensions" (
    map (extension: extension.crxPath) extensions
  );

  darwinSystemModule.homebrew.casks = [
    "ungoogled-chromium"
    # "firefox"
  ];

  sharedHomeModule.programs.chromium = {
    enable = true;
    inherit extensions;
  };

  darwinHomeModule.programs.chromium.package = null;

  nixosHomeModule = { pkgs, ... }: {
    programs.chromium.package = pkgs.ungoogled-chromium;

    wayland.windowManager.hyprland.settings.bind = [
      "$mod, B, exec, chromium"
    ];
  };
}
