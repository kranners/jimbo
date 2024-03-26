{pkgs, ...}: {
  programs.waybar = {
    enable = true;
    
    systemd.enable = true;

    settings = [
      {
        height = 20;
        layer = "top";
        position = "top";

        modules-left = ["wireplumber" "clock"];
        modules-center = ["sway/workspaces"];
        modules-right = ["tray"];

        clock = {
          format-alt = "{:%Y-%m-%d}";
          tooltip-format = "{:%Y-%m-%d | %H:%M}";
        };

        wireplumber = {
          format = "{icon} {volume}%";
          format-muted = "";
          on-click = "${pkgs.pavucontrol}/bin/pavucontrol";
          format-icons = ["" "" ""];
        };
      }
    ];
  };
}
