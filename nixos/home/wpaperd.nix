{ config, ... }: {
  services.wpaperd = {
    enable = true;
    settings.default = {
      path = config.xdg.userDirs.pictures;
      sorting = "random";
      duration = "30m";
    };
  };
}
