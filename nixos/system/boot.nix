{ pkgs, ... }: {
  # For GRUB autodetection
  environment.systemPackages = [ pkgs.os-prober ];

  boot.loader = {
    efi.canTouchEfiVariables = true;
    grub = {
      enable = true;
      devices = [ "nodev" ];
      efiSupport = true;
      useOSProber = true;
    };
  };
}
