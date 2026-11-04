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
  runnerHome = config.users.users.backlogic-runner.home;
  runnerCheckout = "${runnerHome}/workspace/backlogic--service";
  runnerConfigDir = "/var/lib/backlogic-runner-config";
  aaronHome = config.home-manager.users.aaron;
  runnerTokens = "${runnerHome}/.config/github-tokens";
  quietMinutes = 30;

  # Each Claude account the runner launches on has its own config directory, named in
  # runner.json's accounts, every one with aaron's settings. Its sessions load only the
  # repository's instructions, so his CLAUDE.md and skills stay out.
  runnerClaudeDirs = [
    ".claude"
    ".claude-work"
  ];

  # Runner sessions run at medium effort, aaron's own at the high his settings carry.
  runnerClaudeSettings = pkgs.runCommand "runner-claude-settings.json" { } ''
    ${pkgs.jq}/bin/jq '.effortLevel = "medium"' ${
      aaronHome.home.file.".claude/settings.json".source
    } > $out
  '';

  # Answers git over HTTPS with the fine-grained token of the repository's owner, one per
  # owner, since a fine-grained token reaches the repositories of one owner alone.
  github-token-credential = pkgs.writeShellApplication {
    name = "github-token-credential";
    text = ''
      [ "$1" = get ] || exit 0
      while IFS='=' read -r key value && [ -n "$key" ]; do
        [ "$key" = path ] && owner=''${value%%/*}
      done
      token="${runnerTokens}/''${owner:?git sent no path}"
      [ -r "$token" ] || exit 0
      echo username=x-access-token
      echo "password=$(cat "$token")"
    '';
  };

  # Read after aaron's git config, so its gh helper is cleared for the runner's own.
  runnerGitConfig = pkgs.writeText "backlogic-runner-gitconfig" ''
    [credential "https://github.com"]
    	helper =
    	helper = ${lib.getExe github-token-credential}
    	useHttpPath = true
  '';
  aaronUidGid = "1000:100";

  # The runner reaches aaron for Bowerbird's bin/deploy alone, its key's forced command in bowerbird.nix.
  # The key itself, ~/.ssh/bowerbird-deploy, was made by hand and never enters the store.
  runnerKnownHosts = pkgs.writeText "backlogic-runner-known-hosts" ''
    localhost ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICx43TohNiz/wJmnsiv1PzwVeVRRp3PhBTMFs5Ho9cp9
  '';
  runnerSshConfig = pkgs.writeText "backlogic-runner-ssh-config" ''
    Host bowerbird-deploy
      HostName localhost
      User aaron
      IdentityFile ~/.ssh/bowerbird-deploy
      IdentitiesOnly yes
      StrictHostKeyChecking yes
      UserKnownHostsFile ${runnerKnownHosts}
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
      git fetch --quiet origin main
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

  # A session run as aaron could be root through his passwordless sudo, so the runner has
  # its own user, outside wheel, with its own clones under its home.
  users.users.backlogic-runner = {
    isSystemUser = true;
    group = "backlogic-runner";
    home = "/var/lib/backlogic-runner";
    createHome = true;
    shell = pkgs.bashInteractive;
  };
  users.groups.backlogic-runner = { };

  # The instance writes runner.json through a rename as aaron, and the runner and its
  # sessions' hooks read it, so it lives in a directory both reach, its group inherited.
  # The runner's Claude Code and git take aaron's settings, so its sessions behave as his did.
  # Every config directory takes those settings.
  systemd.tmpfiles.rules = [
    "d ${runnerConfigDir} 2750 aaron backlogic-runner -"
  ]
  ++ lib.concatMap (dir: [
    "d ${runnerHome}/${dir} 0700 backlogic-runner backlogic-runner -"
    "L+ ${runnerHome}/${dir}/settings.json - - - - ${runnerClaudeSettings}"
  ]) runnerClaudeDirs
  ++ [
    "d ${runnerHome}/.config 0755 backlogic-runner backlogic-runner -"
    "d ${runnerHome}/.config/git 0755 backlogic-runner backlogic-runner -"
    "L+ ${runnerHome}/.config/git/config - - - - ${aaronHome.xdg.configFile."git/config".source}"
    "L+ ${runnerHome}/.gitconfig - - - - ${runnerGitConfig}"
    "d ${runnerTokens} 0700 backlogic-runner backlogic-runner -"
    "d ${runnerHome}/.ssh 0700 backlogic-runner backlogic-runner -"
    "L+ ${runnerHome}/.ssh/config - - - - ${runnerSshConfig}"
  ];

  # Its sessions run inside the unit, so a switch never restarts it.
  # TMPDIR on tmpfs keeps the checks' fsyncs off the NVMe, and OOMPolicy=continue keeps the
  # other sessions running when one is killed for memory (backlogic's docs/decisions/runner.md).
  # Its weights and memory ceiling leave Bowerbird and the instance the box under pressure.
  # Its own cgroup namespace shows the runner its own memory.max as /sys/fs/cgroup's, so its memory gate
  # judges the room left under its cap, as in a container, rather than the whole box's MemAvailable, which
  # let it launch sessions while its own cgroup sat throttled at MemoryHigh on 4 Nov.
  # Past that, systemd-oomd kills the runner, and only the runner, once its own cgroup has stalled on memory
  # for 30 seconds, and Restart brings it back, so a runaway swarm never drags the rest of spike down.
  systemd.services.backlogic-runner-aaron = {
    description = "backlogic runner launching sessions on Aaron's instance";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [
      "network-online.target"
      "backlogic-aaron.service"
    ];
    restartIfChanged = false;
    unitConfig.ConditionPathExists = "${runnerCheckout}/bin/backlogic-runner";
    path = [
      "/run/wrappers"
      "/run/current-system/sw"
    ];
    environment = {
      TMPDIR = "/dev/shm";
      BACKLOGIC_LAND_QUEUE = "${runnerHome}/land-queue";
    };
    serviceConfig = {
      User = "backlogic-runner";
      WorkingDirectory = runnerCheckout;
      ExecStart = lib.escapeShellArgs [
        "${runnerCheckout}/bin/backlogic-runner"
        "--url"
        "http://127.0.0.1:4200"
        "--workspace"
        "${runnerHome}/workspace"
        "--state"
        "${runnerHome}/state"
        "--config"
        "${runnerConfigDir}/runner.json"
        "--token-file"
        "${runnerHome}/runner.token"
      ];
      OOMPolicy = "continue";
      Restart = "always";
      RestartSec = 30;
      Nice = 10;
      CPUWeight = 20;
      IOWeight = 20;
      MemoryHigh = "6G";
      MemoryMax = "8G";
      MemorySwapMax = "2G";
      TasksMax = 1024;
      CPUQuota = "600%";
      ProtectControlGroups = "private";
      ManagedOOMMemoryPressure = "kill";
      ManagedOOMMemoryPressureLimit = "60%";
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
