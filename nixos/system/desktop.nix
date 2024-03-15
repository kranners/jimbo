{pkgs, ...}: {
  services.xserver = {
    # Enable the X11 windowing system.
    enable = true;

    # Use the AMD video drivers
    videoDrivers = ["amdgpu"];

    # Configure keymap in X11
    xkb = {
      layout = "au";
      variant = "";
    };

    displayManager = {
      sddm = {
        enable = true;
        wayland.enable = true;
      };

      sessionPackages = [
        pkgs.hyprland
      ];
    };
  };

  # Required for Steam to launch
  hardware.opengl = {
    enable = true;
    driSupport = true;
    driSupport32Bit = true;
  };

  fonts.packages = with pkgs; [
    font-awesome
    nerdfonts
    fira-code-nerdfont
  ];
}
