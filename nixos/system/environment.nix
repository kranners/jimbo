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

      # Required by waybar and dunst
      libnotify
    ];

    variables = {
      EDITOR = "vim";
    };
  };
}
