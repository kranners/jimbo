{
  # Security
  security = {
    polkit.enable = true;

    pam.services.swaylock = {
      text = ''
        auth include login
      '';
    };
  };
}
