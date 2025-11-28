{
  networking.firewall.enable = false;

  security = {
    polkit.enable = true;
    sudo.wheelNeedsPassword = false;

    pam.services.swaylock = {
      text = ''
        auth include login
      '';
    };
  };
}
