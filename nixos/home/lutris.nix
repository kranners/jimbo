{ config, pkgs, lib, inputs, ... }: {
  home.packages = [ pkgs.lutris pkgs.wine pkgs.gamemode pkgs.mangohud ];

  # This desktop entry makes this setup non-declarative, since you need to have Battle.net installed
  # for it to function.
  xdg.desktopEntries.battlenet = {
    type = "Application";
    name = "Blizzard Battle.net";
    icon = "lutris_battlenet";
    exec = "env LUTRIS_SKIP_INIT=1 lutris lutris:rungame/battlenet";
    categories = [ "Game" ];
  };
}
