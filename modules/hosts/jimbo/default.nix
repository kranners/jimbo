{ host, ... }: {
  imports = [
    ./hardware.nix
    ./state-versions.nix
  ];

  nixosSystemModule = { pkgs, ... }: {
    networking.hostName = host.hostname;

    environment.systemPackages = [ pkgs.efibootmgr ];

    boot.loader = {
      efi.canTouchEfiVariables = true;
      systemd-boot = {
        enable = true;
        configurationLimit = 5;
      };
    };

    environment.variables.AMD_VULKAN_ICD = "RADV";
  };
}
