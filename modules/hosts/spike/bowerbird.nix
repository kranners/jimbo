{
  config,
  pkgs,
  ...
}:
let
  checkout = "/srv/bowerbird";
  home = "/var/lib/bowerbird";
  backups = "/var/lib/bowerbird-backups";
  display = ":99";
  composeFile = "${checkout}/compose.production.yml";
  compose = "${config.virtualisation.docker.package}/bin/docker compose --project-name bowerbird --file ${composeFile}";
  portal = "app.bowerbird.cute.engineer";

  bowerbird-display = pkgs.writeShellApplication {
    name = "bowerbird-display";
    runtimeInputs = [
      pkgs.xorg.xorgserver
      pkgs.xorg.xdpyinfo
      pkgs.openbox
    ];
    text = ''
      Xvfb ${display} -screen 0 1440x900x24 -nolisten tcp &
      trap 'kill $!' EXIT
      until xdpyinfo -display ${display} > /dev/null 2>&1; do sleep 0.2; done
      DISPLAY=${display} openbox
    '';
  };

  bowerbird-remote-view = pkgs.writeShellApplication {
    name = "bowerbird-remote-view";
    runtimeInputs = [
      pkgs.x11vnc
      pkgs.xorg.xdpyinfo
      pkgs.python3Packages.websockify
    ];
    text = ''
      until xdpyinfo -display ${display} > /dev/null 2>&1; do sleep 0.2; done
      websockify --web ${pkgs.novnc}/share/webapps/novnc 6080 localhost:5900 &
      trap 'kill $!' EXIT
      x11vnc -display ${display} -localhost -rfbport 5900 -nopw -forever -shared -quiet
    '';
  };

  bowerbird-wait-for-postgres = pkgs.writeShellApplication {
    name = "bowerbird-wait-for-postgres";
    runtimeInputs = [ pkgs.postgresql ];
    text = ''
      for _ in $(seq 150); do
        pg_isready --host 127.0.0.1 --port 5432 --quiet && exit 0
        sleep 2
      done
      exit 1
    '';
  };

  bowerbird-backup = pkgs.writeShellApplication {
    name = "bowerbird-backup";
    runtimeInputs = [ pkgs.gzip ];
    text = ''
      ${compose} exec --no-TTY postgres pg_dump --username bowerbird bowerbird \
        | gzip > ${backups}/bowerbird-"$(date +%F)".sql.gz
      find ${backups} -name 'bowerbird-*.sql.gz' -mtime +14 -delete
    '';
  };
in
{
  users.users.bowerbird = {
    isSystemUser = true;
    group = "bowerbird";
    inherit home;
  };
  users.groups.bowerbird = { };

  users.users.aaron.openssh.authorizedKeys.keys = [
    ''restrict,command="${checkout}/bin/deploy" ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINT4kcEV+h7YOOgCnRftVu+KaZJ8o1mM6rtRoOeshOGx github-actions@bowerbird''
  ];

  systemd.tmpfiles.rules = [
    "d ${checkout} 0755 aaron users -"
    "d ${home} 0750 bowerbird bowerbird -"
    "d ${backups} 0750 root root -"
  ];

  fonts.enableDefaultPackages = true;

  environment.systemPackages = [ pkgs.nodejs_24 ];

  services.caddy.virtualHosts.${portal}.extraConfig = ''
    handle_path /vnc/* {
      forward_auth 127.0.0.1:3000 {
        uri /api/auth/ok
      }
      reverse_proxy 127.0.0.1:6080
    }
    handle {
      reverse_proxy 127.0.0.1:3000
    }
  '';

  systemd.services.bowerbird-compose = {
    description = "Bowerbird Postgres and portal";
    wantedBy = [ "multi-user.target" ];
    requires = [ "docker.service" ];
    after = [
      "docker.service"
      "network-online.target"
    ];
    unitConfig.ConditionPathExists = composeFile;
    environment.REMOTE_VIEW_URL = "https://${portal}/vnc/vnc.html?autoconnect=1&resize=scale&path=/vnc/";
    serviceConfig = {
      WorkingDirectory = checkout;
      ExecStart = "${compose} up --build";
      Restart = "on-failure";
      RestartSec = 10;
    };
  };

  systemd.services.bowerbird-display = {
    description = "Bowerbird virtual display";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      User = "bowerbird";
      ExecStart = "${bowerbird-display}/bin/bowerbird-display";
      Restart = "always";
      RestartSec = 5;
    };
  };

  systemd.services.bowerbird-remote-view = {
    description = "Bowerbird remote view of the virtual display";
    wantedBy = [ "multi-user.target" ];
    requires = [ "bowerbird-display.service" ];
    after = [ "bowerbird-display.service" ];
    serviceConfig = {
      User = "bowerbird";
      ExecStart = "${bowerbird-remote-view}/bin/bowerbird-remote-view";
      Restart = "always";
      RestartSec = 5;
    };
  };

  systemd.services.bowerbird-worker = {
    description = "Bowerbird worker";
    wantedBy = [ "multi-user.target" ];
    requires = [ "bowerbird-display.service" ];
    wants = [
      "bowerbird-compose.service"
      "network-online.target"
    ];
    after = [
      "bowerbird-display.service"
      "bowerbird-compose.service"
      "network-online.target"
    ];
    unitConfig.ConditionPathExists = [
      "${checkout}/jobs/src/worker.ts"
      "${checkout}/node_modules"
    ];
    path = [
      pkgs.nodejs_24
      pkgs.google-chrome
      pkgs.procps
      pkgs.xdg-utils
      pkgs.bash
    ];
    environment = {
      DISPLAY = display;
      CHROME_PATH = "${pkgs.google-chrome}/bin/google-chrome-stable";
      BOWERBIRD_HOME = home;
    };
    serviceConfig = {
      User = "bowerbird";
      WorkingDirectory = "${checkout}/jobs";
      ExecStartPre = "${bowerbird-wait-for-postgres}/bin/bowerbird-wait-for-postgres";
      ExecStart = "${pkgs.nodejs_24}/bin/node --env-file-if-exists=${checkout}/.env src/worker.ts";
      KillMode = "mixed";
      TimeoutStopSec = "35min";
      Restart = "on-failure";
      RestartSec = 60;
    };
  };

  systemd.services.bowerbird-backup = {
    description = "Bowerbird nightly database dump";
    requires = [ "docker.service" ];
    after = [ "docker.service" ];
    unitConfig.ConditionPathExists = composeFile;
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${bowerbird-backup}/bin/bowerbird-backup";
    };
  };

  systemd.timers.bowerbird-backup = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "03:00";
      Persistent = true;
    };
  };
}
