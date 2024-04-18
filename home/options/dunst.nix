{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: {
  services.dunst = {
    enable = true;
  };
}
