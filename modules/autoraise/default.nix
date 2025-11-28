{
  darwinSystemModule = {
    homebrew = {
      taps = [ "dimentium/autoraise" ];

      brews = [
        {
          name = "autoraise";
          args = [ "with-dalternative-task-switcher" ];
          restart_service = "changed";
        }
      ];
    };

    security.accessibilityPrograms = [ "/opt/homebrew/Cellar/autoraise/5.3/bin/AutoRaise" ];
  };

  darwinHomeModule = {
    xdg.configFile.autoraise = {
      target = "./AutoRaise/config";

      text = ''
        warpX=0.5
        warpY=0.5
        scale=1
        altTaskSwitcher=true
        ignoreSpaceChanged=true
        invertIgnoreApps=true
      '';
    };
  };
}
