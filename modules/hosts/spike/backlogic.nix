{
  config,
  lib,
  pkgs,
  ...
}:
let
  home = "/home/aaron";
  checkout = "/srv/backlogic";
  dataDir = "${home}/backlogic-data/aaron";
  updatesDir = "${dataDir}/updates";
  runnerConfigDir = config.backlogicRunner.configDir;
  quietMinutes = 30;

  aaronUidGid = "1000:100";

  # The runner reaches aaron for Bowerbird's bin/deploy alone, its key's forced command in bowerbird.nix.
  # The key itself, ~/.ssh/bowerbird-deploy, was made by hand and never enters the store.
  runnerKnownHosts = pkgs.writeText "backlogic-runner-known-hosts" ''
    localhost ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICx43TohNiz/wJmnsiv1PzwVeVRRp3PhBTMFs5Ho9cp9
  '';
  lanInterfaces = [
    "wlp2s0"
    "wg0"
  ];

  # As aaron, the owner's admin verbs keep sharing the store, and runner.json lands in runnerConfigDir with its group.
  # compose.yaml takes no --config, so the entrypoint is the image's own with it added.
  # On the host's network, :4200 stays behind spike's firewall and the peer resolves through spike's /etc/hosts.
  composeOverride = pkgs.writeText "backlogic-spike.yaml" ''
    services:
      backlogic:
        user: "${aaronUidGid}"
        network_mode: host
        ports: !reset []
        entrypoint:
          - deno
          - run
          - --quiet
          - --allow-net
          - --allow-read
          - --allow-write
          - --allow-env
          - --allow-sys=hostname
          - src/server/main.ts
          - --config
          - ${runnerConfigDir}/runner.json
        volumes:
          - ${dataDir}:/data
          - ${runnerConfigDir}:${runnerConfigDir}
  '';

  backlogic-compose = pkgs.writeShellApplication {
    name = "backlogic-compose";
    runtimeInputs = [
      config.virtualisation.docker.package
      pkgs.git
    ];
    text = ''
      BACKLOGIC_COMMIT=$(git -C ${checkout} rev-parse HEAD | cut -c1-7)
      export BACKLOGIC_COMMIT
      export BACKLOGIC_NAME="Aaron's instance"
      export BACKLOGIC_PROJECT=bowerbird
      export BACKLOGIC_PEER="Rylee's instance"
      export BACKLOGIC_PEER_URL=https://ideas.noodlebra.in
      export BACKLOGIC_PEER_TOKEN_FILE=${dataDir}/tokens/peer-rylee.token
      export BACKLOGIC_PEER_OWNER=ibrokemypie
      export BACKLOGIC_UPDATES_DIR=${updatesDir}
      export BACKLOGIC_PROMETHEUS_URL=http://127.0.0.1:9090
      exec docker compose --project-directory ${checkout} --file ${checkout}/compose.yaml --file ${composeOverride} "$@"
    '';
  };

  # The owner's admin verbs open the store itself, so they run the code the instance runs.
  backlogic = pkgs.writeShellScriptBin "backlogic" ''
    PATH=${pkgs.deno}/bin:$PATH exec ${checkout}/bin/backlogic "$@"
  '';

  # Rebuilds the instance from backlogic's main, following the updates folder it shares with
  # the instance's Windows Update (backlogic's docs/decisions/update-notice.md).
  # Each fetch touches `checked`, then writes the waiting commit and its changelog lines to `available`, and installs the commit
  # an owner chose in `install`, refusing one not on main or one the instance already passed.
  # While `automatic` is there it also checks out each main once it has stayed put for
  # quietMinutes, so a run of landings costs one build and one restart, skipping one that failed.
  # A target that does not descend from the running commit is refused, so older code never opens a store newer code migrated.
  # A build that fails puts the checkout back and records the target in `failed`.
  # One that builds keeps its checkout even when it fails to start, since it may already have migrated the store.
  # Once it is up, each of aaron's Claude configs takes main's backlogic plugin, since a third-party
  # marketplace updates only when a session starts, and when that update changed what the plugin
  # prints and the plugin's commit is the checkout's, a fresh Haiku session in each checks the whole base arrived
  # (backlogic's docs/decisions/rule-layers.md).
  backlogic-switch = pkgs.writeShellApplication {
    name = "backlogic-switch";
    runtimeInputs = [
      backlogic-compose
      pkgs.bash
      pkgs.claude-code
      pkgs.deno
      pkgs.findutils
      pkgs.git
      pkgs.gnused
      pkgs.jq
      pkgs.openssh
    ];
    text = ''
      failed_record="${updatesDir}/failed"
      pending_record="$STATE_DIRECTORY/pending"
      refresh_record="$STATE_DIRECTORY/plugin-refresh-failed"

      installed_plugin_version() {
        claude plugin list --json | jq -r '.[] | select(.id == "backlogic@backlogic") | .version'
      }
      # The marketplace serves main, so the plugin can be ahead of a commit an owner chose, and
      # rules-fresh-session compares what arrived against this checkout's rules.
      # A retry checks the rules whenever the plugin is at the checkout, since the update it retries may already have taken.
      # It runs as an if condition, where errexit is off, so each step returns its own failure.
      update_plugin() {
        local version_before version_after
        claude plugin marketplace update backlogic || return
        version_before=$(installed_plugin_version) || return
        claude plugin update backlogic@backlogic || return
        version_after=$(installed_plugin_version) || return
        if [ "$1" != retry ] && { [ "$version_before" = "$version_after" ] \
          || [ -z "$(git diff --name-only "$version_before" "$version_after" -- rules .claude-plugin hooks 2>/dev/null || echo unknown)" ]; }; then
          return 0
        fi
        if [[ "$(git rev-parse HEAD)" != "$version_after"* ]]; then
          echo "Not checking the rules arrived: the plugin is at $version_after, the checkout at $(git rev-parse --short HEAD)" >&2
          return 0
        fi
        bin/rules-fresh-session
      }
      # A refresh or one of the plugin's hooks failing never fails the switch, whose result is the rebuild's:
      # it is logged and recorded, and the next run retries it once.
      # ~/.claude is the default config, whose .claude.json sits in the home, not inside it as CLAUDE_CONFIG_DIR would read it.
      refresh_plugins() {
        local mode=''${1:-first} failed=""
        update_plugin "$mode" || failed="$failed ~/.claude"
        CLAUDE_CONFIG_DIR=${home}/.claude-work update_plugin "$mode" || failed="$failed ~/.claude-work"
        if [ -z "$failed" ]; then
          rm -f "$refresh_record"
        elif [ "$mode" = retry ]; then
          echo "The backlogic plugin refresh failed again in$failed; not retrying it until the next rebuild" >&2
          rm -f "$refresh_record"
        else
          echo "The backlogic plugin refresh failed in$failed; the next run retries it once" >&2
          touch "$refresh_record"
        fi
      }
      # Every run that rebuilds nothing retries a refresh the last rebuild left failed.
      finish() {
        if [ -e "$refresh_record" ]; then
          echo "Retrying the backlogic plugin refresh that failed last run"
          refresh_plugins retry
        fi
        exit 0
      }
      running=$(git rev-parse HEAD)
      ${lib.getExe config.spike.github.retry} git fetch --quiet origin main
      latest=$(git rev-parse FETCH_HEAD)

      # Records the look in `checked`, then offers main and the changelog lines it adds to the
      # instance, or nothing once it runs main.
      write_available() {
        touch "${updatesDir}/checked"
        if [ "$latest" = "$(git rev-parse HEAD)" ]; then
          rm -f "${updatesDir}/available"
          return
        fi
        {
          echo "$latest"
          git diff --unified=0 HEAD "$latest" -- CHANGELOG.md | sed -n 's/^+- //p'
        } > "${updatesDir}/available.tmp"
        mv "${updatesDir}/available.tmp" "${updatesDir}/available"
      }
      write_available

      chosen=$(cat "${updatesDir}/install" 2>/dev/null || true)
      rm -f "${updatesDir}/install"
      if [ -n "$chosen" ] && ! git merge-base --is-ancestor "$chosen" "$latest" 2>/dev/null; then
        echo "Not installing $chosen: it is not on main" >&2
        chosen=""
      elif [ -n "$chosen" ] && git merge-base --is-ancestor "$chosen" "$running"; then
        echo "Not installing $chosen: the instance already runs it or a later commit" >&2
        chosen=""
      fi

      if [ -n "$chosen" ]; then
        target=$(git rev-parse "$chosen^{commit}")
      elif [ -e "${updatesDir}/automatic" ]; then
        target=$latest
        if [ "$target" = "$running" ] || [ "$target" = "$(cat "$failed_record" 2>/dev/null)" ]; then
          finish
        fi
        if [ "$target" != "$(cat "$pending_record" 2>/dev/null)" ]; then
          echo "$target" > "$pending_record"
          finish
        fi
        if [ -z "$(find "$pending_record" -mmin +${toString quietMinutes})" ]; then
          finish
        fi
      else
        finish
      fi

      if ! git merge-base --is-ancestor "$running" "$target"; then
        echo "$target does not descend from the running $running" >&2
        echo "$target" > "$failed_record"
        exit 1
      fi

      git checkout --quiet --detach "$target"
      if ! backlogic-compose build; then
        git checkout --quiet --detach "$running"
        echo "$target" > "$failed_record"
        exit 1
      fi

      rm -f "$failed_record"
      write_available
      backlogic-compose up --detach --wait

      refresh_plugins
    '';
  };
  backlogic-switch-streak = pkgs.writeShellApplication {
    name = "backlogic-switch-streak";
    text = ''
      streak="$STATE_DIRECTORY/failed-runs"
      if [ "$SERVICE_RESULT" = success ]; then
        rm -f "$streak"
      else
        echo $(( $(cat "$streak" 2>/dev/null || echo 0) + 1 )) > "$streak"
      fi
    '';
  };
in
{
  environment.systemPackages = [
    backlogic
    backlogic-compose
  ];

  systemd.services.backlogic-aaron = {
    description = "Aaron's backlogic instance, built in Docker from ${checkout}";
    wantedBy = [ "multi-user.target" ];
    requires = [ "docker.service" ];
    wants = [ "network-online.target" ];
    after = [
      "docker.service"
      "network-online.target"
    ];
    unitConfig.ConditionPathExists = "${checkout}/compose.yaml";
    # The updates folder starts with `automatic` once, so spike installs every push until an owner turns it off.
    preStart = ''
      if mkdir ${updatesDir} 2>/dev/null; then
        echo on > ${updatesDir}/automatic
      fi
    '';
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "aaron";
      ExecStart = "${lib.getExe backlogic-compose} up --detach --build --wait";
      ExecStop = "${lib.getExe backlogic-compose} stop";
    };
  };

  systemd.services.backlogic-switch = {
    description = "Rebuild Aaron's backlogic instance when backlogic's main moved";
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    unitConfig.ConditionPathExists = "${checkout}/.git";
    # The plugin's hooks and backlogic's bin/ scripts run under `env bash` and call whatever tools aaron has,
    # so the unit has the system's path, as the runner's sessions do.
    path = [
      "/run/wrappers"
      "/run/current-system/sw"
    ];
    serviceConfig = {
      Type = "oneshot";
      User = "aaron";
      WorkingDirectory = checkout;
      StateDirectory = "backlogic-switch";
      ExecStart = lib.getExe backlogic-switch;
      # Counts failed runs in a row for butler-monitor, which tells Aaron only once there are failStreak of them.
      ExecStopPost = lib.getExe backlogic-switch-streak;
    };
  };

  # The runner, shared with the NUC through modules/backlogic-runner, with spike's own caps.
  # Its weights and memory ceiling leave Bowerbird and the instance the box under pressure.
  backlogicRunner = {
    enable = true;
    after = [ "backlogic-aaron.service" ];
    sshConfig = ''
      Host bowerbird-deploy
        HostName localhost
        User aaron
        IdentityFile ~/.ssh/bowerbird-deploy
        IdentitiesOnly yes
        StrictHostKeyChecking yes
        UserKnownHostsFile ${runnerKnownHosts}
    '';
    memoryHigh = "6G";
    memoryMax = "8G";
    memorySwapMax = "2G";
    tasksMax = 4096;
    cpuQuota = "600%";
    # 64 sessions never binds: launches stop at a load of 8, one per thread, or once the runner
    # holds 70% of its 8G, 5.6G, under MemoryHigh's 6G, and resume as either clears.
    gates = {
      sessions = 64;
      loadPerCpu = 1.0;
      memoryAvailableFloor = 0.3;
    };
  };

  systemd.timers.backlogic-switch = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2min";
      OnUnitInactiveSec = "1min";
    };
  };

  services.caddy.virtualHosts."backlogic.spike.cute.engineer".extraConfig = ''
    reverse_proxy 127.0.0.1:4200
  '';

  networking.firewall.interfaces = lib.genAttrs lanInterfaces (_: {
    allowedTCPPorts = [ 4200 ];
  });
}
