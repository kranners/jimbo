{
  config,
  pkgs,
  inputs,
  ...
}: {
  nixpkgs.overlays = [
    (final: prev: {
      # Patches the rofi plugins to work using rofi-wayland
      # This overlay may be permanent!
      # See: https://discourse.nixos.org/t/rofi-on-wayland-and-plugins/17354/4
      # See: https://github.com/NixOS/nixpkgs/issues/265122
      rofi-calc = prev.rofi-calc.override {rofi-unwrapped = prev.rofi-wayland-unwrapped;};
      rofi-emoji = prev.rofi-emoji.override {rofi-unwrapped = prev.rofi-wayland-unwrapped;};

      # Patches the Davinci Resolve package to allow for OpenCL support
      # https://discourse.nixos.org/t/davinci-resolve-studio-install-issues/37699/44
      davinci-resolve = prev.davinci-resolve.override (old: {
        buildFHSEnv = a: (old.buildFHSEnv (a
          // {
            extraBwrapArgs =
              a.extraBwrapArgs
              ++ [
                "--bind /run/opengl-driver/etc/OpenCL /etc/OpenCL"
              ];
          }));
      });
    })
  ];
}
