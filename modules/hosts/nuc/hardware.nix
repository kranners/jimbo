{ lib, modulesPath, ... }:
let
  # nixos-anywhere writes the NUC's hardware report here when it installs (scripts/nuc-install), and until then
  # the generic x86 modules stand in, enough to evaluate and to boot the usual NUC's NVMe or SATA disk.
  report = ./facter.json;
in
{
  imports = lib.optional (!lib.pathExists report) (modulesPath + "/installer/scan/not-detected.nix");

  hardware.facter.reportPath = lib.mkIf (lib.pathExists report) report;

  boot.initrd.availableKernelModules = lib.mkIf (!lib.pathExists report) [
    "xhci_pci"
    "ahci"
    "nvme"
    "usbhid"
    "usb_storage"
    "sd_mod"
    "sdhci_pci"
  ];
  boot.kernelModules = [ "kvm-intel" ];

  hardware.enableRedistributableFirmware = true;
  hardware.cpu.intel.updateMicrocode = true;

  nixpkgs.hostPlatform = "x86_64-linux";
}
