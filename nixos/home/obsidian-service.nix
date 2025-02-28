{ pkgs, config, ... }: {
  systemd.user.services.obsidian = {
    Unit = {
      Description = "Obsidian (sent to tray)";
      PartOf = [ config.wayland.systemd.target ];
      After = [ config.wayland.systemd.target ];
      ConditionEnvironment = "WAYLAND_DISPLAY";
    };

    Service = {
      ExecStart = "${pkgs.obsidian}/bin/obsidian";
      Restart = "on-failure";
    };

    Install.WantedBy = [ "hyprland-session.target" ];
  };
}

