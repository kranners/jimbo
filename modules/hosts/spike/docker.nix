{
  virtualisation.docker = {
    enable = true;

    # backlogic-switch rebuilds backlogic's image on every move of its main, leaving the old one,
    # and its builds leave cache, so every image no container uses goes once it is a day old.
    # Volumes are never pruned, since Bowerbird's Postgres lives in a named one.
    autoPrune = {
      enable = true;
      dates = "daily";
      flags = [
        "--all"
        "--filter"
        "until=24h"
      ];
    };
  };
}
