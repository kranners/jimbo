{ pkgs, inputs, ... }: {
  imports = [ inputs.walker.homeManagerModules.default];

  home.packages = [ pkgs.libqalculate ];

  wayland.windowManager.hyprland.settings."$menu" = "walker";

  programs.walker = {
    enable = true;
    runAsService = true;

    config.builtins = {
      calc.min_chars = 1;
      applications.actions.enabled = false;
    };
  };
}
