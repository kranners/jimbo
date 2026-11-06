# Aaron's kanban board (kranners/kanban) as a service of spike's own, so spike holds the board, its cards,
# regions, notes, Butler's cards and messages, and pilot, piggys-MBP and jimbo only run sessions for it as runners.
# It is staged: until `kanban-hub cutover` writes the marker, the board stays on pilot behind kanban-tunnel, and
# `kanban-hub scratch` runs a copy of pilot's state on :7430 to test against; `kanban-hub rollback` goes back.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.spike.kanban;
  home = "/var/lib/kanban";
  hubDir = dirOf cfg.hubMarker;
  board = "/run/kanban-tunnel/board.sock";
  repo = "https://github.com/kranners/kanban.git";
  pilot = {
    address = "10.100.0.11";
    user = "aaronpierce";
  };
  # Machines whose runners the board lists as offline until they first check in, by runner id.
  runners = [
    "pilot"
    "piggys-mbp"
    "jimbo"
  ];

  instances = {
    kanban = {
      port = 7420;
      state = "${home}/state";
    };
    kanban-scratch = {
      port = 7430;
      state = "${home}/scratch/state";
    };
  };

  # npm runs every package script with sh, which a systemd unit's PATH lacks, so every build under the timer failed.
  buildInputs = [
    pkgs.bash
    pkgs.nodejs_24
    pkgs.git
    pkgs.gnutar
    pkgs.coreutils
    pkgs.diffutils
    pkgs.findutils
    # node-pty has no Linux prebuild, so npm ci compiles it.
    pkgs.python3
    pkgs.gnumake
    pkgs.gcc
  ];

  # Fetches kranners/kanban's main and, when it moved, builds it into releases/<rev> and points `current` at it,
  # reusing the last release's node_modules while the lockfile is unchanged, so a run of landings stays cheap.
  # A build that fails leaves `current` where it was, and the next commit on main, or a changed updater, is tried afresh.
  update = pkgs.writeShellApplication {
    name = "kanban-update";
    runtimeInputs = buildInputs;
    text = ''
      cd ${home}
      export HOME=${home} npm_config_update_notifier=false npm_config_fund=false npm_config_audit=false
      [ -d repo.git ] || git clone --quiet --bare ${repo} repo.git
      git --git-dir repo.git fetch --quiet origin '+refs/heads/main:refs/heads/main'
      rev=$(git --git-dir repo.git rev-parse main)
      running=$(basename "$(readlink -f current 2> /dev/null || echo none)")
      [ "$rev" != "$running" ] || exit 0
      # A failure is recorded with this script's own store path, so a fixed updater retries the same commit.
      attempt="$rev $(readlink -f "$0")"
      [ "$attempt" != "$(cat failed 2> /dev/null || true)" ] || exit 0
      release=releases/$rev
      rm -rf "$release.new"
      mkdir -p "$release.new"
      git --git-dir repo.git archive "$rev" | tar -x -C "$release.new"
      if [ -d current/node_modules ] && cmp -s current/package-lock.json "$release.new/package-lock.json"; then
        cp -a current/node_modules "$release.new/"
      fi
      if ! (cd "$release.new" && { [ -d node_modules ] || npm ci --no-audit --no-fund; } && npm run build); then
        echo "kanban-update: $rev failed to build, staying on $running" >&2
        echo "$attempt" > failed
        rm -rf "$release.new"
        exit 1
      fi
      rm -rf "$release"
      mv "$release.new" "$release"
      ln -sfn "$release" current.new
      mv -T current.new current
      rm -f failed
      echo "kanban-update: built $rev"
      # Tells the restart which release to put back, and what to record, should the new one not answer.
      printf '%s\n%s\n' "$running" "$attempt" > updated
      # Keeps the release running and the one before, for a quick step back.
      find releases -mindepth 1 -maxdepth 1 -type d ! -name "$rev" ! -name "$running" -exec rm -rf {} +
    '';
  };

  # Copies pilot's board state, never moving or deleting it, imports it into an instance and checks it arrived whole.
  hub = pkgs.writeShellApplication {
    name = "kanban-hub";
    runtimeInputs = [
      pkgs.openssh
      pkgs.gnutar
      pkgs.gzip
      pkgs.coreutils
      pkgs.jq
      pkgs.curl
      pkgs.systemd
      pkgs.util-linux
    ];
    text = builtins.readFile ./kanban/kanban-hub.sh;
    # The script quotes commands for pilot's shell to expand, ~ and $(id -u) among them.
    excludeShellChecks = [
      "SC2016"
      "SC2088"
    ];
    runtimeEnv = {
      HOME_DIR = home;
      MARKER = cfg.hubMarker;
      PILOT = "${pilot.user}@${pilot.address}";
      UPDATE = lib.getExe update;
      LIVE_STATE = instances.kanban.state;
      SCRATCH_STATE = instances.kanban-scratch.state;
      LIVE_PORT = toString instances.kanban.port;
      SCRATCH_PORT = toString instances.kanban-scratch.port;
    };
  };

  serve =
    name:
    pkgs.writeShellScript "${name}-serve" ''
      token=/run/${name}/runner-token
      if [ -s "$token" ]; then
        KANBAN_RUNNER_TOKEN=$(cat "$token")
        export KANBAN_RUNNER_TOKEN
      fi
      exec ${lib.getExe pkgs.nodejs_24} ${home}/current/src/server/main.ts
    '';

  service = name: instance: {
    description =
      if name == "kanban" then
        "Aaron's kanban board, held on spike for every machine"
      else
        "A scratch kanban board on :${toString instance.port}, for testing an import of pilot's state";
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    path = [
      pkgs.git
      pkgs.claude-code
      pkgs.coreutils
    ];
    environment = {
      HOME = home;
      KANBAN_AUTH = "off";
      KANBAN_HOST = "127.0.0.1";
      KANBAN_PORT = toString instance.port;
      KANBAN_STATE = instance.state;
      KANBAN_AUDIT_LOG = "${dirOf instance.state}/audit.jsonl";
      KANBAN_DIST = "${home}/current/dist";
      KANBAN_RUNNERS = lib.concatStringsSep "," runners;
      # Spike runs no sessions of its own for the board, so its Claude home stays the service's own.
      CLAUDE_HOME = "${home}/.claude";
      CLAUDE_CONFIG_DIR = "${home}/.claude";
      CLAUDE_BIN = lib.getExe pkgs.claude-code;
    };
    unitConfig = {
      ConditionPathExists = "${home}/current/src/server/main.ts";
      StartLimitIntervalSec = 0;
    };
    serviceConfig = {
      User = "kanban";
      Group = "kanban";
      RuntimeDirectory = name;
      RuntimeDirectoryMode = "0700";
      # The runners' shared token, written by hand or by `kanban-hub token`, and handed over without the store.
      ExecStartPre =
        "+"
        + pkgs.writeShellScript "${name}-token" ''
          f=/var/lib/secrets/kanban-runner-token
          [ -s "$f" ] || exit 0
          install -m 400 -o kanban -g kanban "$f" /run/${name}/runner-token
        '';
      ExecStart = serve name;
      Restart = "always";
      # Back at once after a crash, backing off to 30 seconds while a broken release keeps crashing.
      RestartSec = 1;
      RestartSteps = 5;
      RestartMaxDelaySec = 30;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      NoNewPrivileges = true;
      ReadWritePaths = [ home ];
    };
  };

  # Whether the board answers on its port, and through Caddy's socket, with any HTTP status at all.
  probes = ''
    direct() { curl --silent --output /dev/null --max-time 3 http://127.0.0.1:${toString instances.kanban.port}/; }
    socket() { curl --silent --output /dev/null --max-time 3 --unix-socket ${board} http://127.0.0.1:${toString instances.kanban.port}/; }
    wait_for() { for _ in $(seq 1 "$2"); do if "$1"; then return 0; fi; sleep 0.5; done; return 1; }
  '';

  restart = pkgs.writeShellApplication {
    name = "kanban-update-restart";
    # wait_for calls the probes by name, which shellcheck cannot see.
    excludeShellChecks = [ "SC2329" ];
    runtimeInputs = [
      pkgs.coreutils
      pkgs.curl
      pkgs.systemd
    ];
    text = probes + ''
      [ -e ${home}/updated ] || exit 0
      { read -r previous; read -r attempt; } < ${home}/updated || true
      rm -f ${home}/updated
      systemctl restart kanban.service
      systemctl start kanban-bridge.socket
      if wait_for direct 120; then
        echo "kanban-update: the board answers on its new release"
        wait_for socket 20 || echo "kanban-update: the board answers, but not yet through Caddy's socket" >&2
        exit 0
      fi
      echo "kanban-update: the new release did not answer within 60 seconds" >&2
      if [ -n "''${previous:-}" ] && [ -d "${home}/releases/$previous" ]; then
        ln -sfn "releases/$previous" ${home}/current.new
        chown -h kanban:kanban ${home}/current.new
        mv -T ${home}/current.new ${home}/current
        printf '%s\n' "$attempt" > ${home}/failed
        chown kanban:kanban ${home}/failed
        systemctl restart kanban.service
        if wait_for direct 120; then echo "kanban-update: put $previous back" >&2; else echo "kanban-update: $previous does not answer either" >&2; fi
      fi
      exit 1
    '';
  };

  health = pkgs.writeShellApplication {
    name = "kanban-health";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.curl
      pkgs.gawk
      pkgs.systemd
    ];
    text = probes + ''
      state=/var/lib/kanban-health
      cd "$state"
      # An update restarting the board waits for it itself.
      [ "$(systemctl show -p ActiveState --value kanban-update.service)" != activating ] || exit 0
      if direct && socket; then
        rm -f fails
        exit 0
      fi
      fails=$(( $(cat fails 2> /dev/null || echo 0) + 1 ))
      echo "$fails" > fails
      if [ "$fails" -lt 2 ]; then
        echo "kanban-health: the board did not answer, trying again in 30 seconds"
        exit 0
      fi
      if direct; then
        what="kanban-bridge.socket kanban-bridge.service"
      else
        what="kanban.service"
      fi
      echo "kanban-health: the board failed twice in a row, restarting $what" >&2
      # shellcheck disable=SC2086
      systemctl restart $what
      systemctl start kanban-bridge.socket
      rm -f fails
      now=$(date +%s)
      echo "$now $what" >> actions
      awk -v since=$((now - 86400)) '$1 >= since' actions > actions.new && mv actions.new actions
      recent=$(awk -v since=$((now - 3600)) '$1 >= since' actions | wc -l)
      if [ "$recent" -gt 1 ] && [ "$(cat told 2> /dev/null || echo 0)" -lt $((now - 3600)) ]; then
        echo "$now" > told
        /run/current-system/sw/bin/butler-notify <<EOF || true
      The kanban board on spike stopped answering $recent times in the last hour, and spike restarted it each time ($what last). It is back, but something keeps knocking it over: journalctl -u kanban -u kanban-bridge -u kanban-health says what.
      EOF
      fi
    '';
  };

  # Kills the board and the bridge, as a crash would, and checks the board answers through Caddy's socket again
  # within 10 seconds, as root on spike: sudo kanban-recovery-check.
  recovery = pkgs.writeShellApplication {
    name = "kanban-recovery-check";
    # wait_for calls the probes by name, which shellcheck cannot see.
    excludeShellChecks = [ "SC2329" ];
    runtimeInputs = [
      pkgs.coreutils
      pkgs.curl
      pkgs.gawk
      pkgs.systemd
    ];
    text = probes + ''
      [ "$(id -u)" = 0 ] || { echo "kanban-recovery-check: run it with sudo" >&2; exit 2; }
      [ -e ${cfg.hubMarker} ] || { echo "kanban-recovery-check: the board does not run on spike" >&2; exit 2; }
      socket || { echo "kanban-recovery-check: the board does not answer through the socket to begin with" >&2; exit 1; }
      start=$(date +%s.%N)
      systemctl kill --signal=SIGKILL kanban.service kanban-bridge.service
      sleep 0.2
      if wait_for socket 20; then
        echo "kanban-recovery-check: the board answered through the socket again after $(awk -v a="$start" -v b="$(date +%s.%N)" 'BEGIN { printf "%.1f", b - a }') seconds"
      else
        echo "kanban-recovery-check: the board did not answer within 10 seconds" >&2
        exit 1
      fi
    '';
  };

  # Only these users reach the boards' ports on loopback: the board trusts a loopback caller with no Origin as a
  # local agent or Butler, so no other user on spike, backlogic's runner sessions above all, may act as one.
  allowed = [
    "root"
    "butler"
    "kanban"
  ];
  loopbackChain = iptables: ''
    ${iptables} -D OUTPUT -o lo -j kanban-loopback 2> /dev/null || true
    ${iptables} -F kanban-loopback 2> /dev/null || true
    ${iptables} -X kanban-loopback 2> /dev/null || true
    ${iptables} -N kanban-loopback
    ${lib.concatMapStrings (
      instance:
      lib.concatMapStrings (user: ''
        ${iptables} -A kanban-loopback -p tcp --dport ${toString instance.port} -m owner --uid-owner ${user} -j RETURN
      '') allowed
      + ''
        ${iptables} -A kanban-loopback -p tcp --dport ${toString instance.port} -j REJECT --reject-with tcp-reset
      ''
    ) (lib.attrValues instances)}
    ${iptables} -I OUTPUT -o lo -j kanban-loopback
  '';
in
{
  options.spike.kanban.hubMarker = lib.mkOption {
    type = lib.types.str;
    default = "/var/lib/kanban-hub/on-spike";
    readOnly = true;
    description = "The file whose presence says the board runs on spike rather than on pilot behind kanban-tunnel.";
  };

  config = {
    users.users.kanban = {
      isSystemUser = true;
      group = "kanban";
      inherit home;
      # So the bridge, as kanban, serves the socket Caddy reads in kanban-tunnel's place.
      extraGroups = [ "kanban-tunnel" ];
    };
    users.groups.kanban = { };

    systemd.tmpfiles.settings.kanban = {
      ${home}.d = {
        user = "kanban";
        group = "kanban";
        mode = "0750";
      };
      "${home}/releases".d = {
        user = "kanban";
        group = "kanban";
        mode = "0750";
      };
      "${home}/backups".d = {
        user = "root";
        group = "root";
        mode = "0700";
      };
      ${hubDir}.d = {
        user = "root";
        group = "root";
        mode = "0755";
      };
    };

    environment.systemPackages = [
      hub
      recovery
    ];

    systemd.services = {
      kanban-scratch = service "kanban-scratch" instances.kanban-scratch;

      kanban = service "kanban" instances.kanban // {
        wantedBy = [ "multi-user.target" ];
        unitConfig = {
          ConditionPathExists = [
            cfg.hubMarker
            "${home}/current/src/server/main.ts"
          ];
          StartLimitIntervalSec = 0;
        };
      };

      # Carries Caddy's connections from the socket to the board, in kanban-tunnel's place. systemd itself holds the
      # socket, kanban-bridge.socket, so it never vanishes while the proxy or the board restarts, and the proxy
      # dials the board afresh for each connection, so it needs no tie to kanban.service: on 6 Nov 2026 its
      # BindsTo= stopped it with the board's restart, socat's exit 143 marked it failed, and the board answered
      # every request 502 for five minutes, runners' heartbeats included.
      kanban-bridge = {
        description = "Carry Caddy's connections to the kanban board on spike";
        requires = [ "kanban-bridge.socket" ];
        after = [ "kanban-bridge.socket" ];
        unitConfig = {
          ConditionPathExists = cfg.hubMarker;
          StartLimitIntervalSec = 0;
        };
        serviceConfig = {
          # The loopback chain lets kanban reach the board's port.
          User = "kanban";
          Group = "kanban";
          ExecStart = "${pkgs.systemd}/lib/systemd/systemd-socket-proxyd 127.0.0.1:${toString instances.kanban.port}";
          Restart = "always";
          RestartSec = 1;
          SuccessExitStatus = [
            143
            "SIGTERM"
          ];
          PrivateTmp = true;
          NoNewPrivileges = true;
          ProtectSystem = "strict";
          ProtectHome = true;
        };
      };

      # Every 30 seconds, asks the board through Caddy's socket and directly, and after two failures in a row
      # restarts what failed, telling Aaron only once it has had to act more than once in an hour.
      kanban-health = {
        description = "Check the kanban board answers through Caddy's socket, restarting what does not";
        unitConfig.ConditionPathExists = cfg.hubMarker;
        serviceConfig = {
          Type = "oneshot";
          StateDirectory = "kanban-health";
          ExecStart = lib.getExe health;
        };
      };

      kanban-update = {
        description = "Build kranners/kanban's main for the board on spike, restarting it when its code moved";
        wants = [ "network-online.target" ];
        after = [ "network-online.target" ];
        unitConfig.ConditionPathExists = cfg.hubMarker;
        serviceConfig = {
          Type = "oneshot";
          User = "kanban";
          Group = "kanban";
          Nice = 10;
          ExecStart = lib.getExe update;
          # Restarts the board on the new release, waits for it to answer, and puts the release before back
          # when it does not, so an update never leaves the board down.
          ExecStartPost = "+${lib.getExe restart}";
          TimeoutStartSec = "15min";
        };
      };
    };

    # systemd holds the board's socket for Caddy, mode 0660 in the group kanban-tunnel, which alone holds Caddy.
    systemd.sockets.kanban-bridge = {
      description = "Caddy's socket to the kanban board on spike";
      wantedBy = [ "sockets.target" ];
      unitConfig.ConditionPathExists = cfg.hubMarker;
      socketConfig = {
        ListenStream = board;
        SocketUser = "kanban";
        SocketGroup = "kanban-tunnel";
        SocketMode = "0660";
        DirectoryMode = "0755";
        # So kanban-hub rollback's kanban-tunnel can bind the same path.
        RemoveOnStop = true;
      };
    };

    systemd.timers.kanban-health = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnActiveSec = "1min";
        OnUnitActiveSec = "30s";
        AccuracySec = "1s";
      };
    };

    systemd.timers.kanban-update = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnActiveSec = "1min";
        OnUnitInactiveSec = "1min";
      };
    };

    networking.firewall.extraCommands = loopbackChain "iptables" + loopbackChain "ip6tables";
    networking.firewall.extraStopCommands = ''
      iptables -D OUTPUT -o lo -j kanban-loopback 2> /dev/null || true
      ip6tables -D OUTPUT -o lo -j kanban-loopback 2> /dev/null || true
    '';
  };
}
