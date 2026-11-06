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
      touch updated
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
    unitConfig.ConditionPathExists = "${home}/current/src/server/main.ts";
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
      RestartSec = 5;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      NoNewPrivileges = true;
      ReadWritePaths = [ home ];
    };
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

    environment.systemPackages = [ hub ];

    systemd.services = {
      kanban-scratch = service "kanban-scratch" instances.kanban-scratch;

      kanban = service "kanban" instances.kanban // {
        wantedBy = [ "multi-user.target" ];
        unitConfig = {
          ConditionPathExists = [
            cfg.hubMarker
            "${home}/current/src/server/main.ts"
          ];
        };
      };

      # Serves the socket Caddy proxies the board to from the local board, in kanban-tunnel's place.
      kanban-bridge = {
        description = "Carry Caddy's connections to the kanban board on spike";
        wantedBy = [ "multi-user.target" ];
        bindsTo = [ "kanban.service" ];
        after = [ "kanban.service" ];
        # No Conflicts= with kanban-tunnel: a switch starting this one would stop the tunnel before this one's
        # condition skipped it. The marker keeps the two apart, and kanban-hub stops one before starting the other.
        unitConfig.ConditionPathExists = cfg.hubMarker;
        serviceConfig = {
          User = "kanban";
          Group = "kanban-tunnel";
          RuntimeDirectory = "kanban-tunnel";
          RuntimeDirectoryMode = "0750";
          ExecStart = lib.escapeShellArgs [
            "${pkgs.socat}/bin/socat"
            "UNIX-LISTEN:${board},fork,unlink-early,mode=0660,group=kanban-tunnel"
            "TCP:127.0.0.1:${toString instances.kanban.port}"
          ];
          Restart = "always";
          RestartSec = 5;
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
          ExecStartPost =
            "+"
            + pkgs.writeShellScript "kanban-update-restart" ''
              [ -e ${home}/updated ] || exit 0
              rm -f ${home}/updated
              ${pkgs.systemd}/bin/systemctl restart kanban.service kanban-bridge.service
            '';
          TimeoutStartSec = "15min";
        };
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
