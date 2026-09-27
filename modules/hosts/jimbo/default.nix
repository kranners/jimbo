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

    # Stay reachable for remote OpenClaw jobs: never sleep.
    services.logind.settings.Login.IdleAction = "ignore";

    systemd.targets = {
      sleep.enable = false;
      suspend.enable = false;
      hibernate.enable = false;
      hybrid-sleep.enable = false;
    };
  };
}
