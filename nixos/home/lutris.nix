{ config
, pkgs
, lib
, inputs
, ...
}:
let
  red-alert-path = "${config.home.homeDirectory}/games/Red Alert 3";
in
{
  home.packages = [ pkgs.lutris pkgs.wine-staging pkgs.gamemode pkgs.mangohud ];

  # This desktop entry makes this setup non-declarative, since you need to have Battle.net installed
  # for it to function.
  xdg.desktopEntries.battlenet = {
    type = "Application";
    name = "Blizzard Battle.net";
    icon = "lutris_battlenet";
    exec = "env LUTRIS_SKIP_INIT=1 lutris lutris:rungame/battlenet";
    categories = [ "Game" ];
  };

  xdg.desktopEntries.red-alert-3 = {
    type = "Application";
    name = "Red Alert 3";
    icon = "game";
    exec = "env WINEPREFIX=\"${red-alert-path}\" wine \"${red-alert-path}/RA3.exe\"";
    categories = [ "Game" ];
  };
}
