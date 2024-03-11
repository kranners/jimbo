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
  };

  services.greetd = {
    enable = true;
    settings = rec {
      initial_session = {
        command = "${pkgs.hyprland}/bin/Hyprland";
        user = "aaron";
      };
      default_session = initial_session;
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

    noto-fonts
    noto-fonts-cjk
    noto-fonts-emoji
  ];
}
