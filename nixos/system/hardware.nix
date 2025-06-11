{ config, lib, modulesPath, ... }: {
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  hardware.wooting.enable = true;

  virtualisation.docker.enable = true;

  boot.initrd.availableKernelModules = [ "nvme" "xhci_pci" "ahci" "usbhid" "usb_storage" "sd_mod" ];

  # Enable AMD GPU support
  boot.initrd.kernelModules = [ "amdgpu" ];

  boot.kernelParams = [ "video=DP-1:2560x1440@165" "video=DP-3:1920x1080@144" ];

  boot.kernelModules = [ "kvm-amd" ];
  boot.extraModulePackages = [ ];

  fileSystems."/" = {
    device = "/dev/disk/by-uuid/704dc311-3e07-47f8-91db-49a2a88bc5ab";
    fsType = "ext4";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/0B76-7ECA";
    fsType = "vfat";
  };

  fileSystems."/spare" = {
    device = "/dev/disk/by-uuid/ec6e35df-0c3a-41c5-91e8-57af5b751316";
    fsType = "ext4";
  };

  swapDevices = [
    { device = "/dev/disk/by-uuid/14710369-3de6-4a13-9ad5-6895dd332c3e"; }
  ];

  # Enables DHCP on each ethernet and wireless interface. In case of scripted networking
  # (the default) this is the recommended approach. When using systemd-networkd it's
  # still possible to use this option, but it's recommended to use it in conjunction
  # with explicit per-interface declarations with `networking.interfaces.<interface>.useDHCP`.
  networking.useDHCP = lib.mkDefault true;
  # networking.interfaces.enp42s0.useDHCP = lib.mkDefault true;
  # networking.interfaces.wlo1.useDHCP = lib.mkDefault true;

  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.amd.updateMicrocode =
    lib.mkDefault config.hardware.enableRedistributableFirmware;
}
