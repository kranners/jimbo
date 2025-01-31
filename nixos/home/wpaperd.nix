{ pkgs, config, ... }: {
  programs.wpaperd = {
    enable = true;
    settings = {
      default = {
        path = config.xdg.userDirs.pictures;
        sorting = "random";
        duration = "30m";
      };
    };
  };
  systemd.user.services.wpaperd = {
    Unit = {
      Description = "Wayland wallpaper daemon";
      PartOf = [ config.wayland.systemd.target ];
      After = [ config.wayland.systemd.target ];
      ConditionEnvironment = "WAYLAND_DISPLAY";
    };

    Service = {
      ExecStart = "${pkgs.wpaperd}/bin/wpaperd";
      Restart = "on-failure";
    };

    Install.WantedBy = [ "hyprland-session.target" ];
  };
}
