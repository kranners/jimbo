{
  config,
  pkgs,
  inputs,
  ...
}: {
  nixpkgs.overlays = [
    # Patches the rofi plugins to work using rofi-wayland
    # This overlay may be permanent!
    # See: https://discourse.nixos.org/t/rofi-on-wayland-and-plugins/17354/4
    # See: https://github.com/NixOS/nixpkgs/issues/265122
    (final: prev: {
      rofi-calc = prev.rofi-calc.override {rofi-unwrapped = prev.rofi-wayland-unwrapped;};
      rofi-emoji = prev.rofi-emoji.override {rofi-unwrapped = prev.rofi-wayland-unwrapped;};
    })
  ];
}
