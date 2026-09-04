{
  nixosSystemModule = {
    networking.firewall.enable = false;

    security = {
      polkit.enable = true;
      sudo.wheelNeedsPassword = false;
    };
  };
}
