{ pkgs, ... }: {
  home.packages = [ pkgs.plexamp ];

  wayland.windowManager.sway.config.window.commands = [{
    criteria = { title = "Plexamp"; };
    command = "opacity 0.65";
  }];
}
