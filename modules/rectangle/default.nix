{
  darwinSystemModule.homebrew.casks = [ "rectangle" ];

  darwinHomeModule.launchd.agents.rectangle = {
    enable = true;

    config = {
      ProgramArguments = [ "/Applications/Rectangle.app/Contents/MacOS/Rectangle" ];
      RunAtLoad = true;
      KeepAlive = false;
    };
  };
}
