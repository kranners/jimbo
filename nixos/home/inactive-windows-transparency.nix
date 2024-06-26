{ pkgs, ... }:
let
  # The more recent versions of the inactive-windows-transparency script are super smart
  # and account for multiple monitors & workspaces. This is on purpose.
  # See: https://github.com/swaywm/sway/issues/5372
  very-old-sway = pkgs.fetchFromGitHub {
    owner = "swaywm";
    repo = "sway";
    rev = "0d5aaf5359c671a51bd319bd7972e0f5e7bcde84";
    hash = "sha256-FJ72VQmAchSkkW52fyBV9i2C0Qygaa4GX71IUACYcG0=";
  };

  inactive-window-transparency = pkgs.writeShellApplication {
    name = "inactive-window-transparency";

    runtimeInputs = [
      (pkgs.python3.withPackages (pip: [
        pip.i3ipc
      ]))
    ];

    text = ''
      python3 ${very-old-sway}/contrib/inactive-windows-transparency.py
    '';
  };
in
{
  systemd.user.services.inactive-window-transparency = {
    Install = { WantedBy = [ "sway-session.target" ]; };
    Unit = {
      Description = "It makes inactive sway windows transparent";
      After = [ "graphical-session-pre.target" ];
      PartOf = [ "graphical-session.target" ];
    };

    Service = {
      ExecStart = "${inactive-window-transparency}/bin/inactive-window-transparency";
      Restart = "on-failure";
    };
  };
}
