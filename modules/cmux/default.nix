{
  sharedHomeModule.xdg.configFile.cmux = {
    target = "./cmux/config.json";

    text = builtins.toJSON {
      shortcuts = {
        bindings = {
          focusLeft = "ctrl+cmd+h";
          focusDown = "ctrl+cmd+j";
          focusUp = "ctrl+cmd+k";
          focusRight = "ctrl+cmd+l";

          splitRight = "ctrl+cmd+n";
          splitDown = "ctrl+cmd+shift+n";
        };
      };
    };
  };
}
