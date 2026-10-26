{ inputs, pkgs, ... }:
{
  imports = [ inputs.nixos-hardware.nixosModules.microsoft-surface-common ];

  # https://github.com/NixOS/nixos-hardware/issues/2079
  boot.kernelPatches = [
    {
      name = "rust-softfloat-target-spec";
      patch = pkgs.fetchpatch {
        url = "https://github.com/torvalds/linux/commit/905b06d32a52afe32fcf5f30cf298c9ea6359f11.patch";
        hash = "sha256-G5X1FPewzWACgefquexsbD3wGUAXuStDDbclSMcX4YE=";
      };
    }
  ];

  services.iptsd.enable = true;

  environment.systemPackages = [ pkgs.surface-control ];
}
