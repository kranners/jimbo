{
  config,
  pkgs,
  inputs,
  ...
}: {
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
}
