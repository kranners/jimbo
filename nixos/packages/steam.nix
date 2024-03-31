{
  config,
  pkgs,
  inputs,
  ...
}: {
  programs.steam = {
    enable = true;
    localNetworkGameTransfers.openFirewall = true;
  };

  # Required for Steam to launch
  hardware.opengl = {
    enable = true;
    driSupport = true;
    driSupport32Bit = true;
  };
}
