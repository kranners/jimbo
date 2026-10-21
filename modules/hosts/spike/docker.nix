{
  virtualisation.docker = {
    enable = true;

    # backlogic-switch rebuilds backlogic's image on every move of its main, leaving the old one dangling.
    autoPrune = {
      enable = true;
      dates = "daily";
    };
  };
}
