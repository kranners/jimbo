{ pkgs, config, ... }: {
  home.packages = [ pkgs.kando ];

  systemd.user.services.kando = {
    Unit = {
      Description = "Configurable radial menu for Hyprland";
    };
    Install = { WantedBy = [ config.wayland.systemd.target ]; };
    Service = {
      ExecStart = "${pkgs.kando}/bin/kando";
      Restart = "always";
      RestartSec = "3";
    };
  };

  wayland.windowManager.hyprland.settings = {
    exec-once = [ "uwsm app -- systemctl --user restart kando" ];

    bind = [
      "$mod ALT, SPACE, global, kando:example-menu"
    ];

    windowrule = [
      "noblur, kando"
      "opaque, kando"
      "size 100% 100%, kando"
      "noborder, kando"
      "noanim, kando"
      "float, kando"
      "pin, kando"
    ];
  };
}
