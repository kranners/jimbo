{ pkgs, ... }: {
  system.defaults.NSGlobalDomain._HIHideMenuBar = true;

  services.sketchybar = {
    enable = true;
    extraPackages = with pkgs; [
      jetbrains-mono
    ];
    config = ''
      ############## BAR ##############
        sketchybar -m --bar \
          height=32 \
          position=top \
          padding_left=5 \
          padding_right=5 \
          color=0xff2e3440 \
          shadow=off \
          sticky=on \
          topmost=off

      ############## GLOBAL DEFAULTS ##############
        sketchybar -m --default \
          updates=when_shown \
          drawing=on \
          cache_scripts=on \
          icon.font="JetBrainsMono Nerd Font Mono:Bold:18.0" \
          icon.color=0xffffffff \
          label.font="JetBrainsMono Nerd Font Mono:Bold:12.0" \
          label.color=0xffeceff4 \
          label.highlight_color=0xff8CABC8
    '';
  };
}
