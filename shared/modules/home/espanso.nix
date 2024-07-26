{ pkgs, lib, ... }:
let
  BASE_PATH = "./espanso/match/packages";
  is-linux = pkgs.hostPlatform.isLinux;

  HUB_REPOSITORY = pkgs.fetchFromGitHub {
    owner = "espanso";
    repo = "hub";
    rev = "1fe1b383ecc671640cefd6917e45c0bced459ea1";
    hash = "sha256-XyS+joGtveZs4db1w6j5LPh2YdNKq/FPqW2Gucvn9Cw=";
  };

  PLUGINS = [
    { version = "0.1.0"; name = "all-emojis"; }
    { version = "0.1.0"; name = "lorem"; }
    { version = "0.1.0"; name = "english-lorem"; }
    { version = "0.1.1"; name = "espanso-mac-symbols"; }
    { version = "0.1.0"; name = "shruggie"; }
  ];

  pluginToXdgConfig = plugin: {
    target = "${BASE_PATH}/${plugin.name}";
    recursive = true;

    source = "${HUB_REPOSITORY}/packages/${plugin.name}/${plugin.version}";
  };
in
{
  services.espanso = {
    enable = true;
    package = if is-linux then pkgs.espanso-wayland else pkgs.espanso;
  };

  xdg.configFile = builtins.listToAttrs (
    lib.lists.forEach PLUGINS (plugin: {
      name = plugin.name;
      value = pluginToXdgConfig plugin;
    })
  );
}
