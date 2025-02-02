{ pkgs, inputs, ... }: {
  imports = [ inputs.anyrun.homeManagerModules.default];

  wayland.windowManager.hyprland.settings."$menu" = "anyrun";

  programs.anyrun = {
    enable = true;

    config = {
      plugins = with inputs.anyrun.packages.${pkgs.system}; [
        applications
        randr
        rink
        shell
      ];

      width.fraction = 0.4;
      y.fraction = 0.3;
      hidePluginInfo = true;
      closeOnClick = true;
    };

    # Yoinked from deepanchal
    # https://github.com/anyrun-org/anyrun/discussions/179
    extraCss = ''
      /* GTK Vars */
      @define-color bg-color #313244;
      @define-color fg-color #cdd6f4;
      @define-color primary-color #89b4fa;
      @define-color secondary-color #cba6f7;
      @define-color border-color @primary-color;
      @define-color selected-bg-color @primary-color;
      @define-color selected-fg-color @bg-color;

      * {
        all: unset;
        font-family: JetBrainsMono Nerd Font;
      }

      #window {
        background: transparent;
      }

      box#main {
        border-radius: 16px;
        background-color: alpha(@bg-color, 0.6);
        border: 0.5px solid alpha(@fg-color, 0.25);
      }

      entry#entry {
        font-size: 1.25rem;
        background: transparent;
        box-shadow: none;
        border: none;
        border-radius: 16px;
        padding: 16px 24px;
        min-height: 40px;
        caret-color: @primary-color;
      }

      list#main {
        background-color: transparent;
      }

      #plugin {
        background-color: transparent;
        padding-bottom: 4px;
      }

      #match {
        font-size: 1.1rem;
        padding: 2px 4px;
      }

      #match:selected,
      #match:hover {
        background-color: @selected-bg-color;
        color: @selected-fg-color;
      }

      #match:selected label#info,
      #match:hover label#info {
        color: @selected-fg-color;
      }

      #match:selected label#match-desc,
      #match:hover label#match-desc {
        color: alpha(@selected-fg-color, 0.9);
      }

      #match label#info {
        color: transparent;
        color: @fg-color;
      }

      label#match-desc {
        font-size: 1rem;
        color: @fg-color;
      }

      label#plugin {
        font-size: 16px;
      }
    '';
  };
}
