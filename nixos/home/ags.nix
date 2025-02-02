{ inputs, ... }: {
  home.packages = [ inputs.jimbags.packages.x86_64-linux.default ];

  # See https://github.com/Aylur/ags/blob/main/nix/hm-module.nix
  systemd.user.services.ags = {
    Unit = {
      Description = "ags for jimbo";
      Documentation = "https://github.com/kranners/jimbags";
      PartOf = ["graphical-session.target"];
      After = ["graphical-session-pre.target"];
    };

    Service = {
      ExecStart = "${inputs.jimbags.packages.x86_64-linux.default}/bin/jimbags";
      Restart = "on-failure";
      KillMode = "mixed";
    };

    Install = {
      WantedBy = ["graphical-session.target"];
    };
  };
}
