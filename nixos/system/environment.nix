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
    ];

    variables = {
      KWIN_X11_REFRESH_RATE = "144000";
      KWIN_X11_NO_SYNC_TO_VBLANK = "1";
      KWIN_X11_FORCE_SOFTWARE_VSYNC = "1";
      EDITOR = "vim";
    };
  };
}
