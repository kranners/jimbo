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
    ];

    variables = {
      EDITOR = "vim";
    };
  };
}
