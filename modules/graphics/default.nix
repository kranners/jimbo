{
  nixosSystemModule = { pkgs, ... }: {
    hardware.graphics = {
      enable = true;
      enable32Bit = true;

      extraPackages = [
        pkgs.libva-utils
      ];
    };
  };
}
