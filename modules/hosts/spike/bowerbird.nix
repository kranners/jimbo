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
  houseDisplayNumber = 99;
  tokenFile = "${home}/vnc-tokens";
  databaseUrl = "postgres://bowerbird:bowerbird@127.0.0.1:5432/bowerbird";
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

  # One instance per signed-in member, each its own Xvfb, openbox and
  # x11vnc, so two members' handoffs never share a display; the VNC port
  # is derived from the display number so it never collides with another
  # member's or the house's own `5900`, which nothing watches any more.
  bowerbird-member-display = pkgs.writeShellApplication {
    name = "bowerbird-member-display";
    runtimeInputs = [
      pkgs.xorg.xorgserver
      pkgs.xorg.xdpyinfo
      pkgs.openbox
      pkgs.x11vnc
    ];
    text = ''
      display_number="$1"
      vnc_port=$((5900 + display_number - ${toString houseDisplayNumber}))

      Xvfb ":$display_number" -screen 0 1440x900x24 -nolisten tcp &
      xvfb_pid=$!
      until xdpyinfo -display ":$display_number" > /dev/null 2>&1; do sleep 0.2; done

      DISPLAY=":$display_number" openbox &
      openbox_pid=$!
      trap 'kill "$xvfb_pid" "$openbox_pid"' EXIT

      x11vnc -display ":$display_number" -localhost -rfbport "$vnc_port" -nopw -forever -shared -quiet
    '';
  };

  # One shared proxy rather than one per member: websockify's own
  # `TokenFile` plugin picks the target by the `?token=` a member's own
  # remote view URL already carries, read fresh from `tokenFile` on every
  # connection, so a rotated token or a new member needs no restart.
  bowerbird-vnc-proxy = pkgs.writeShellApplication {
    name = "bowerbird-vnc-proxy";
    runtimeInputs = [ pkgs.python3Packages.websockify ];
    text = ''
      websockify --web ${pkgs.novnc}/share/webapps/novnc \
        --token-plugin TokenFile --token-source ${tokenFile} \
        6080
    '';
  };

  # Keeps `tokenFile` and the set of running `bowerbird-display@` instances
  # in sync with `members.displayNumber`/`vncToken` in Postgres; runs on the
  # host, on a timer, since Postgres is reachable from here but a schema
  # change or a rotated token has nothing on the portal side to notify it.
  bowerbird-sync-displays = pkgs.writeShellApplication {
    name = "bowerbird-sync-displays";
    runtimeInputs = [
      pkgs.postgresql
      pkgs.systemd
    ];
    text = ''
      mapfile -t rows < <(psql ${databaseUrl} --no-align --tuples-only --field-separator=' ' \
        -c 'select display_number, vnc_token from members')

      declare -A wanted
      tmp="$(mktemp)"
      for row in "''${rows[@]}"; do
        read -r display_number vnc_token <<< "$row"
        [ -z "$display_number" ] && continue
        vnc_port=$((5900 + display_number - ${toString houseDisplayNumber}))
        echo "$vnc_token: 127.0.0.1:$vnc_port" >> "$tmp"
        wanted[$display_number]=1
      done
      install -m 640 -o bowerbird -g bowerbird "$tmp" ${tokenFile}
      rm -f "$tmp"

      mapfile -t units < <(systemctl list-units --all --plain --no-legend 'bowerbird-display@*.service' | awk '{print $1}')
      for unit in "''${units[@]}"; do
        instance="''${unit#bowerbird-display@}"
        instance="''${instance%.service}"
        if [ -z "''${wanted[$instance]:-}" ]; then
          systemctl stop "$unit"
        fi
      done

      for display_number in "''${!wanted[@]}"; do
        systemctl start "bowerbird-display@$display_number.service"
      done
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
    "f ${tokenFile} 0640 bowerbird bowerbird -"
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

  # Instanced per member by display number, starting and stopping under
  # bowerbird-sync-displays rather than wantedBy, since which members exist
  # is a fact in Postgres rather than something known at switch time.
  systemd.services."bowerbird-display@" = {
    description = "Bowerbird virtual display and remote view for member %i";
    serviceConfig = {
      User = "bowerbird";
      ExecStart = "${bowerbird-member-display}/bin/bowerbird-member-display %i";
      Restart = "always";
      RestartSec = 5;
    };
  };

  systemd.services.bowerbird-vnc-proxy = {
    description = "Bowerbird remote view proxy, routed per member by VNC token";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      User = "bowerbird";
      ExecStart = "${bowerbird-vnc-proxy}/bin/bowerbird-vnc-proxy";
      Restart = "always";
      RestartSec = 5;
    };
  };

  systemd.services.bowerbird-sync-displays = {
    description = "Sync per-member VNC tokens and displays from Postgres";
    requires = [ "docker.service" ];
    after = [
      "docker.service"
      "bowerbird-compose.service"
    ];
    unitConfig.ConditionPathExists = composeFile;
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${bowerbird-sync-displays}/bin/bowerbird-sync-displays";
    };
  };

  systemd.timers.bowerbird-sync-displays = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "1min";
      OnUnitActiveSec = "1min";
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
