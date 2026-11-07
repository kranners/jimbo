{
  config,
  lib,
  pkgs,
  host,
  ...
}:
let
  inherit (lib) mkOption types;
  cfg = config.backlogicRunner;

  runnerHome = "/var/lib/backlogic-runner";
  runnerCheckout = "${runnerHome}/workspace/backlogic--service";
  aaronHome = config.home-manager.users.${host.username};
  runnerTokens = "${runnerHome}/.config/github-tokens";

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

  # A unit's path entries are bin directories, so mise's shims are linked in as one.
  miseShims = pkgs.runCommand "mise-shims" { } ''
    mkdir $out
    ln -s ${runnerHome}/.local/share/mise/shims $out/bin
  '';

  gib = n: "${toString n}G";

  # The gates the module owns in runner.json, the rest of which the instance writes.
  gatesFile = pkgs.writeText "backlogic-runner-gates.json" (
    builtins.toJSON {
      inherit (cfg.gates)
        sessions
        loadPerCpu
        memoryAvailableFloor
        peerCloudClaims
        accountCeilings
        ;
    }
  );

  # The gates' oneshot, merging them into runner.json, in ./gates.nix so the flake check can run it.
  backlogic-runner-gates = import ./gates.nix {
    inherit pkgs gatesFile;
    inherit (cfg) configDir;
  };
in
{
  options.backlogicRunner = {
    enable = lib.mkEnableOption "backlogic's runner, launching Claude Code sessions for a backlogic instance as the system user backlogic-runner";

    url = mkOption {
      description = "The backlogic instance the runner claims tickets from.";
      type = types.str;
      default = "http://127.0.0.1:4200";
    };

    configDir = mkOption {
      description = "Where runner.json lives, written by the instance on spike, or copied in by hand on a host that runs no instance.";
      type = types.str;
      default = "/var/lib/backlogic-runner-config";
    };

    after = mkOption {
      description = "Units the runner starts after, besides the network.";
      type = types.listOf types.str;
      default = [ ];
    };

    sshConfig = mkOption {
      description = "The runner's ~/.ssh/config, or none when empty.";
      type = types.lines;
      default = "";
    };

    memoryGiB = mkOption {
      description = "The machine's memory in GiB, from which the runner's memory and task caps are derived.";
      type = types.ints.positive;
      default = 16;
    };

    cores = mkOption {
      description = "The machine's CPU threads, from which the runner's CPU quota is derived.";
      type = types.ints.positive;
      default = 4;
    };

    # The runner's own memory gate launches a session only while gates.memoryAvailableFloor of its cgroup's
    # memory.max is free, so MemoryMax, with the load gate, is its concurrency ceiling.
    memoryMax = mkOption {
      description = "The runner's hard memory cap, and so its concurrency ceiling; by default all but 3 GiB of the machine's memory.";
      type = types.str;
      default = gib (lib.max 2 (cfg.memoryGiB - 3));
    };

    memoryHigh = mkOption {
      description = "Where the kernel starts throttling the runner; by default 1 GiB under memoryMax.";
      type = types.str;
      default = gib (lib.max 1 (cfg.memoryGiB - 4));
    };

    memorySwapMax = mkOption {
      description = "How much swap the runner may use, since a cap that leaves swap free still spends RAM on zram.";
      type = types.str;
      default = "2G";
    };

    tasksMax = mkOption {
      description = "The runner's task cap, high enough that the memory gate holds launches before forks fail; by default 512 a thread.";
      type = types.ints.positive;
      default = 512 * cfg.cores;
    };

    # The runner's own launch gates, which the module writes into runner.json, so machine
    # resources rather than a count decide how many sessions run at once.
    gates = {
      sessions = mkOption {
        description = "runner.json's `sessions`, the most host sessions at once, set high enough that the load and memory gates bind first.";
        type = types.ints.positive;
        default = 64;
      };

      loadPerCpu = mkOption {
        description = "runner.json's `loadPerCpu`: the one-minute load per CPU, over every CPU of the machine, past which no session launches.";
        type = types.numbers.positive;
        default = 1.0;
      };

      memoryAvailableFloor = mkOption {
        description = "runner.json's `memoryAvailableFloor`: the share of the runner's own memoryMax that must be free for a launch, which its cgroup namespace shows it as the container's cap.";
        type = types.numbers.between 0 1;
        default = 0.3;
      };

      # A peer's tickets are its owner's, and her own runner works them, so by default
      # no cloud session claims one or fences one into its batch, and none holds a cloud slot.
      # Its host sessions still need a checkout of the ticket's project, so they pass over
      # every peer project but the shared ones.
      peerCloudClaims = mkOption {
        description = "runner.json's `peerCloudClaims`: the most cloud sessions at once on tickets copied from a peer instance, 0 to work none of them in the cloud.";
        type = types.ints.unsigned;
        default = 0;
      };

      # An account's own usage ceilings in runner.json, merged into its entry of `accounts`, so
      # the module keeps them as it keeps the gates above, until Pulse's usage governor sets them itself.
      accountCeilings = mkOption {
        description = "Usage ceilings per account name, merged into that account's entry of runner.json's `accounts`; accounts not named keep their own.";
        type = types.attrsOf (
          types.submodule {
            options = {
              fiveHourCeiling = mkOption {
                description = "The share of the 5-hour window the account may reach, or false to turn that gate off.";
                type = types.nullOr (types.either (types.enum [ false ]) (types.numbers.between 0 1));
                default = null;
              };
              sevenDayPacing = mkOption {
                description = "The share of the week's headroom, above the share of the week gone, the account may use, or false to turn the weekly gate off.";
                type = types.nullOr (types.either (types.enum [ false ]) (types.numbers.between 0 1));
                default = null;
              };
              sevenDayLimit = mkOption {
                description = "The weekly use the account's pacing ceiling never passes.";
                type = types.nullOr (types.numbers.between 0 1);
                default = null;
              };
            };
          }
        );
        default = { };
        example = {
          cloud-work-2.sevenDayLimit = 0.95;
        };
        apply = lib.mapAttrs (_: lib.filterAttrs (_: v: v != null));
      };
    };

    cpuQuota = mkOption {
      description = "The runner's CPU quota; by default every thread but one.";
      type = types.str;
      default = "${toString (100 * lib.max 1 (cfg.cores - 1))}%";
    };
  };

  config = lib.mkIf cfg.enable {
    # A session run as aaron could be root through his passwordless sudo, so the runner has
    # its own user, outside wheel, with its own clones under its home.
    users.users.backlogic-runner = {
      isSystemUser = true;
      group = "backlogic-runner";
      home = runnerHome;
      createHome = true;
      shell = pkgs.bashInteractive;
    };
    users.groups.backlogic-runner = { };

    # The instance writes runner.json through a rename as aaron, and the runner and its
    # sessions' hooks read it, so it lives in a directory both reach, its group inherited.
    # The runner's Claude Code and git take aaron's settings, so its sessions behave as his did.
    # Every config directory takes those settings.
    systemd.tmpfiles.rules = [
      "d ${cfg.configDir} 2750 ${host.username} backlogic-runner -"
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
    ]
    ++
      lib.optional (cfg.sshConfig != "")
        "L+ ${runnerHome}/.ssh/config - - - - ${pkgs.writeText "backlogic-runner-ssh-config" cfg.sshConfig}";

    # Its sessions run inside the unit, so a switch never restarts it.
    # TMPDIR on tmpfs keeps the checks' fsyncs off the disk, and OOMPolicy=continue keeps the
    # other sessions running when one is killed for memory (backlogic's docs/decisions/runner.md).
    # Its weights and memory ceiling leave the rest of the machine room under pressure.
    # Its own cgroup namespace shows the runner its own memory.max as /sys/fs/cgroup's, so its memory gate
    # judges the room left under its cap, as in a container, rather than the whole box's MemAvailable, which
    # let it launch sessions while its own cgroup sat throttled at MemoryHigh on 4 Nov.
    # Past that, systemd-oomd kills the runner, and only the runner, once its own cgroup has stalled on memory
    # for 30 seconds, and Restart brings it back, so a runaway swarm never drags the rest of the machine down.
    # mise's shims come last on its PATH, so its sessions find bin/check's tools.
    systemd.services.backlogic-runner-aaron = {
      description = "backlogic runner launching sessions on Aaron's instance";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ] ++ cfg.after;
      restartIfChanged = false;
      unitConfig.ConditionPathExists = "${runnerCheckout}/bin/backlogic-runner";
      path = lib.mkMerge [
        [
          "/run/wrappers"
          "/run/current-system/sw"
        ]
        (lib.mkAfter [ miseShims ])
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
          cfg.url
          "--workspace"
          "${runnerHome}/workspace"
          "--state"
          "${runnerHome}/state"
          "--config"
          "${cfg.configDir}/runner.json"
          "--token-file"
          "${runnerHome}/runner.token"
        ];
        OOMPolicy = "continue";
        Restart = "always";
        RestartSec = 30;
        Nice = 10;
        CPUWeight = 20;
        IOWeight = 20;
        MemoryHigh = cfg.memoryHigh;
        MemoryMax = cfg.memoryMax;
        MemorySwapMax = cfg.memorySwapMax;
        TasksMax = cfg.tasksMax;
        CPUQuota = cfg.cpuQuota;
        ProtectControlGroups = "private";
        ManagedOOMMemoryPressure = "kill";
        ManagedOOMMemoryPressureLimit = "60%";
      };
    };

    # Writes the gates into runner.json on each switch that changes them, as the owner, whose
    # directory it is, skipping a host where no runner.json is there yet.
    systemd.services.backlogic-runner-gates = {
      description = "the backlogic runner's launch gates written into runner.json";
      wantedBy = [ "multi-user.target" ];
      inherit (cfg) after;
      unitConfig.ConditionPathExists = "${cfg.configDir}/runner.json";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = host.username;
        StateDirectory = "backlogic-runner-gates";
        ExecStart = lib.getExe backlogic-runner-gates;
      };
    };
  };
}
