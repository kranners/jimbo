{ pkgs, config, ... }:
let
  random-background-and-theme = pkgs.writeShellApplication {
    name = "randomize-background";

    runtimeInputs = [ pkgs.stylish pkgs.pywal pkgs.python2 ];

    text = ''
      styli.sh -y --search "beautiful,hd" --width 2560 --height 1440 
      wal -i "${config.xdg.cacheHome}/styli.sh/wallpaper.jpg"
      systemctl --user restart swaybg 
    '';
  };
in
{
  home.packages = [ random-background-and-theme ];

  systemd.user.services.swaybg = {
    Unit = {
      Description = "Background service, using the most recent from styli.sh";
    };
    Install = { WantedBy = [ "sway-session.target" ]; };
    Service = {
      ExecStart = "${pkgs.swaybg}/bin/swaybg --image ${config.xdg.cacheHome}/styli.sh/wallpaper.jpg";
      Restart = "always";
      RestartSec = "3";
    };
  };

  home.pointerCursor = {
    package = pkgs.catppuccin-cursors.latteDark;
    gtk.enable = true;

    name = "Catppuccin-Latte-Dark-Cursors";
  };

  wayland.windowManager.sway.extraConfig = ''
    include ${config.xdg.cacheHome}/wal/colors-sway
  '';

  programs.waybar = {
    settings.main = {
      reload_style_on_change = true;
    };

    style = ''
      @import url("${config.xdg.cacheHome}/wal/colors-waybar.css");
    '';
  };
}
