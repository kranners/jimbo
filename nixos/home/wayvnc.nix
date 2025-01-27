{ pkgs, config, ... }: {
  home.packages = [ pkgs.wayvnc ];

  xdg.configFile."wayvnc/config" = {
    text = ''
      enable_auth = false
      address = 0.0.0.0
    '';
  };

  systemd.user.services.wayvnc = {
    Unit = {
      Description = "Wayland VNC server";
      ConditionEnvironment = "WAYLAND_DISPLAY";
      PartOf = [ "graphical-session.target" ];
    };

    Service = {
      ExecStart = "${pkgs.wayvnc}/bin/wayvnc --output=DP-2 --log-level=debug";
      Restart = "on-failure";
    };

    Install.WantedBy = [ config.wayland.systemd.target ];
  };
}
