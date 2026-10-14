{
  config,
  modulesPath,
  pkgs,
  ...
}:
{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  boot.initrd.availableKernelModules = [
    "xhci_pci"
    "nvme"
    "usb_storage"
    "sd_mod"
  ];
  boot.kernelModules = [ "kvm-intel" ];

  fileSystems."/" = {
    device = "/dev/disk/by-uuid/a5593f6a-385f-4e97-94ed-ed334bbe77cc";
    fsType = "ext4";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/8F85-F71B";
    fsType = "vfat";
    options = [
      "fmask=0077"
      "dmask=0077"
    ];
  };

  nixpkgs.hostPlatform = "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = config.hardware.enableRedistributableFirmware;

  # A Surface Book 2, so it has a battery and no wired network, and needs the
  # power daemons a desktop does not.
  #
  # Bluetooth stays off: linux-surface documents the Marvell wifi as
  # unreliable while it is on.
  hardware.bluetooth.enable = false;
  hardware.bluetooth.powerOnBoot = false;

  # The ALC298's mic jack once read plugged in from boot with nothing in it,
  # moving capture off the internal mic to a silent jack, so jack detection
  # is off and the internal mic and speakers are always used.
  boot.extraModprobeConfig = "options snd-hda-intel patch=framer-no-jack-detect.fw";
  hardware.firmware = [
    (pkgs.writeTextDir "lib/firmware/framer-no-jack-detect.fw" ''
      [codec]
      0x10ec0298 0x10ec1146 0

      [hint]
      jack_detect = false
    '')
  ];

  services.thermald.enable = true;
  services.upower.enable = true;
}
