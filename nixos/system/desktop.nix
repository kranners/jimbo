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
        # TODO: This currently just lets you straight through to the main window. That's no bueno.
        # Let's add an actual login screen here.
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
    nerdfonts
    fira-code-nerdfont
  ];
}
