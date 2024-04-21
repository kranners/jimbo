{ config, pkgs, lib, inputs, ... }:
let
  vesktop-with-flags = pkgs.writeShellApplication {
    name = "vesktop";

    runtimeInputs = [ pkgs.vesktop ];

    # Run Vesktop with forced Wayland flags
    text = ''
      vesktop                                      \
        --enable-features=WaylandWindowDecorations \
        --ozone-platform-hint=auto                 \
        --use-gl=angle                             \
        --use-angle=gl                             \
        --enable-features=VaapiVideoDecodeLinuxGL,VaapiVideoEncoder,VaapiVP8Encoder,VaapiVP9Encoder,VaapiAV1Encoder,VaapiIgnoreDriverChecks,VaapiVideoDecoder,CanvasOopRasterization,UseMultiPlaneFormatForHardwareVideo
    '';
  };
in {
  home.packages = [ vesktop-with-flags ];

  xdg.desktopEntries.vesktop = {
    name = "Vesktop";
    # The "vesktop" called here is the one provided by vesktop-with-flags
    exec = "vesktop %U";
    terminal = false;
    icon = "Vesktop";
    categories = [ "Network" ];
  };
}
