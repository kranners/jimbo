{ host, ... }: {
  imports = [
    ./hardware.nix
    ./state-versions.nix
  ];

  nixosSystemModule = { pkgs, ... }: {
    networking.hostName = host.hostname;

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

    environment.variables.AMD_VULKAN_ICD = "RADV";
  };
}
