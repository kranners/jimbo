{ config, lib, ... }:
let
  cfg = config.nuc;
in
{
  options.nuc = {
    disk = lib.mkOption {
      description = "The one disk nixos-anywhere wipes and installs to; /dev/sda on a NUC with a SATA disk, from lsblk on the installer.";
      type = lib.types.str;
      default = "/dev/nvme0n1";
    };

    memoryGiB = lib.mkOption {
      description = "The NUC's memory in GiB, from which its swap and the backlogic runner's caps are derived.";
      type = lib.types.ints.positive;
      default = 16;
    };

    cores = lib.mkOption {
      description = "The NUC's CPU threads.";
      type = lib.types.ints.positive;
      default = 4;
    };

    swapSize = lib.mkOption {
      description = "The swap partition's size, half the memory by default and at most 8G, beside zram.";
      type = lib.types.str;
      default = "${toString (lib.min 8 (lib.max 2 (cfg.memoryGiB / 2)))}G";
    };
  };

  config = {
    # One GPT disk: a 1G ESP for systemd-boot, swap, and ext4 on the rest.
    disko.devices.disk.main = {
      type = "disk";
      device = cfg.disk;
      content = {
        type = "gpt";
        partitions = {
          ESP = {
            size = "1G";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = [ "umask=0077" ];
            };
          };
          swap = {
            size = cfg.swapSize;
            content.type = "swap";
          };
          root = {
            size = "100%";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/";
            };
          };
        };
      };
    };

    zramSwap.enable = true;
  };
}
