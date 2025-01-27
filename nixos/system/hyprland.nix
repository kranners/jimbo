{
  programs.hyprland = {
    enable = true;
    withUWSM = true;
  };

  programs.uwsm.enable = true;

  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        command = "uwsm start hyprland-uwsm.desktop";
        user = "aaron";
      };
    };
  };

  environment.sessionVariables.NIXOS_OZONE_WL = "1";
}
