{ config, pkgs, inputs, ... }: {
  # Required by the Chili SDDM theme
  environment.systemPackages = [
    pkgs.libsForQt5.qt5.qtgraphicaleffects
    pkgs.libsForQt5.qt5.qtquickcontrols2
  ];

  services.displayManager = {
    sddm = {
      enable = true;
      wayland.enable = true;

      theme = "${pkgs.sddm-chili-theme}/share/sddm/themes/chili";
    };

    sessionPackages = [ pkgs.sway ];
  };
}
