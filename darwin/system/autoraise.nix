{
  homebrew = {
    taps = [ "dimentium/autoraise" ];

    brews = [
      {
        name = "autoraise";
        args = [ "--with-dalternative_task_switcher" ];
        restart_service = "changed";
      }
    ];
  };

  xdg.configFile.autoraise = {
    target = "./AutoRaise/config";

    text = ''
      #AutoRaise config file
      warpX=0.5
      warpY=0.5
      scale=1
      altTaskSwitcher=true
      ignoreSpaceChanged=true
    '';
  };
}
