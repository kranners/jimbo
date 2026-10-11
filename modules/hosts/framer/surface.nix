{ inputs, pkgs, ... }:
{
  imports = [ inputs.nixos-hardware.nixosModules.microsoft-surface-common ];

  services.iptsd.enable = true;

  environment.systemPackages = [ pkgs.surface-control ];
}
