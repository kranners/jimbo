{pkgs, ...}: {
  environment = {
    systemPackages = with pkgs; [
      home-manager

      # For GRUB autodetection
      os-prober

      # Nix development tools
      alejandra
      nixd
      gnumake
      gnupg
      manix

      # It's just really neat
      eza

      # Required by waybar and dunst
      libnotify

      # Required by the Chili SDDM theme
      libsForQt5.qt5.qtgraphicaleffects
      libsForQt5.qt5.qtquickcontrols2
    ];

    variables = {
      EDITOR = "vim";
    };
  };
}
