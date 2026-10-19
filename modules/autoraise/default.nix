{
  darwinSystemModule = {
    homebrew = {
      taps = [ "dimentium/autoraise" ];

      brews = [
        {
          name = "autoraise";
          restart_service = "changed";
        }
      ];
    };
  };

  darwinHomeModule = {
    xdg.configFile.autoraise = {
      target = "./AutoRaise/config";

      text = ''
        delay=0
        warpX=0.5
        warpY=0.5
        scale=1
        altTaskSwitcher=true
        ignoreSpaceChanged=true
      '';
    };
  };
}
