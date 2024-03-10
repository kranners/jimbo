{pkgs, ...}: {
  environment = {
    systemPackages = with pkgs; [
      wget
      vim
      gnupg
      gnumake

      home-manager
      os-prober
      alejandra

      # Required by waybar and dunst
      libnotify
      
      where-is-my-sddm-theme
    ];

    variables = {
      KWIN_X11_REFRESH_RATE = "144000";
      KWIN_X11_NO_SYNC_TO_VBLANK = "1";
      KWIN_X11_FORCE_SOFTWARE_VSYNC = "1";
      EDITOR = "vim";
    };

    sessionVariables = {
      WLR_NO_HARDWARE_CURSORS = "1";
      NIXOS_OZONE_WL = "1";
    };
  };
}
