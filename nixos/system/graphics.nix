{ pkgs, ... }: {
  hardware.graphics = {
    enable = true;
    enable32Bit = true;

    extraPackages = [ pkgs.rocmPackages.clr.icd ];
  };
}
