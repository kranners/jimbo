{ pkgs, ... }: {
  home.packages = [ pkgs.lutris pkgs.wine-staging pkgs.gamemode ];

  xdg.desktopEntries.battlenet = {
    type = "Application";
    name = "Blizzard Battle.net";
    icon = "lutris_battlenet";
    exec = "env LUTRIS_SKIP_INIT=1 lutris lutris:rungame/battlenet";
    categories = [ "Game" ];
  };
}
