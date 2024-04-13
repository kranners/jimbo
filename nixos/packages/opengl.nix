{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: {
  hardware.opengl = {
    enable = true;
    driSupport = true;
    driSupport32Bit = true;

    extraPackages = [pkgs.rocmPackages.clr.icd];
  };
}
