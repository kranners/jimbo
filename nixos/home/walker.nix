{ pkgs, ... }: {
  home.packages = [ pkgs.libqalculate ];
  wayland.windowManager.hyprland.settings."$menu" = "walker";

  programs.walker = {
    enable = true;
    runAsService = true;

    theme = {
      layout = {
        ui.window.box = {
          v_align = "center";
          orientation = "vertical";

          scroll.list.item.icon.theme = "Papirus";
        };
      };

      style = ''
        #window {
          background: none;
        }

        #box {
          background: rgba(0xf0f0f0, 1.0);
          padding: 16px;
          padding-top: 0px;
          border-radius: 8px;
          box-shadow:
            0 19px 38px rgba(0, 0, 0, 0.3),
            0 15px 12px rgba(0, 0, 0, 0.22);
        }
      '';
    };
  };
}
