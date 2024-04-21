{ config, pkgs, inputs, ... }: {
  programs.steam = {
    enable = true;
    localNetworkGameTransfers.openFirewall = true;
  };
}
