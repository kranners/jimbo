{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  home = "/home/aaron";
  checkout = "${home}/workspace/jimbo";
  runnerHome = config.users.users.backlogic-runner.home;
  runnerCheckout = "${runnerHome}/workspace/backlogic--service";
  runnerConfigDir = "/var/lib/backlogic-runner-config";
  aaronHome = config.home-manager.users.aaron;
  runnerTokens = "${runnerHome}/.config/github-tokens";

  # Each Claude account the runner launches on has its own config directory, named in
  # runner.json's accounts, every one with aaron's settings, CLAUDE.md and skills.
  runnerClaudeDirs = [
    ".claude"
    ".claude-bloom"
  ];
  claudeFiles = [
    "settings.json"
    "CLAUDE.md"
    "skills/commit/SKILL.md"
  ];

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

  lanInterfaces = [
    "wlp2s0"
    "wg0"
  ];

  # Bumps the checkout's lock to backlogic's main and switches spike to it when main has moved.
  # A bump that fails to build puts the lock back and is skipped until main moves again.
  # One that builds keeps its lock even when the switch fails, since spike may already run it
  # and a later switch from the older lock would run a backlogic older than its store.
  backlogic-switch = pkgs.writeShellApplication {
    name = "backlogic-switch";
    runtimeInputs = [
      pkgs.git
      pkgs.jq
      pkgs.nh
      pkgs.openssh
    ];
    text = ''
      failed_record="$STATE_DIRECTORY/failed"
      locked=$(jq -r .nodes.backlogic.locked.rev flake.lock)
      latest=$(git ls-remote git@github.com:backlogic/backlogic.git refs/heads/main | cut -f1)
      if [ "$latest" = "$locked" ] || [ "$latest" = "$(cat "$failed_record" 2>/dev/null)" ]; then
        exit 0
      fi

      cp flake.lock "$STATE_DIRECTORY/flake.lock.before"
      if ! nix flake update backlogic || ! nh os build .; then
        cp "$STATE_DIRECTORY/flake.lock.before" flake.lock
        echo "$latest" > "$failed_record"
        exit 1
      fi

      rm -f "$failed_record"
      nh os switch .
    '';
  };
in
{
  imports = [ inputs.backlogic.nixosModules.default ];

  services.backlogic.instances.aaron = {
    port = 4200;
    hostname = "0.0.0.0";
    dataDir = "${home}/backlogic-data/aaron";
    project = "bowerbird";
    displayName = "Aaron's instance";
    user = "aaron";
    runnerConfig = "${runnerConfigDir}/runner.json";
    peer = {
      name = "Rylee's instance";
      url = "https://ideas.noodlebra.in";
      tokenFile = "${home}/backlogic-data/aaron/tokens/peer-rylee.token";
      owner = "ibrokemypie";
    };
  };

  systemd.services.backlogic-switch = {
    description = "Bump jimbo's backlogic input and switch spike to it when backlogic's main moved";
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    path = [
      "/run/wrappers"
      "/run/current-system/sw"
    ];
    unitConfig.ConditionPathExists = "${checkout}/flake.lock";
    serviceConfig = {
      Type = "oneshot";
      User = "aaron";
      WorkingDirectory = checkout;
      StateDirectory = "backlogic-switch";
      ExecStart = lib.getExe backlogic-switch;
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
  # Every config directory takes .claude's files, which are the same in each of aaron's.
  systemd.tmpfiles.rules = [
    "d ${runnerConfigDir} 2750 aaron backlogic-runner -"
  ]
  ++ lib.concatMap (
    dir:
    [
      "d ${runnerHome}/${dir} 0700 backlogic-runner backlogic-runner -"
      "d ${runnerHome}/${dir}/skills/commit 0755 backlogic-runner backlogic-runner -"
    ]
    ++ map (
      file: "L+ ${runnerHome}/${dir}/${file} - - - - ${aaronHome.home.file.".claude/${file}".source}"
    ) claudeFiles
  ) runnerClaudeDirs
  ++ [
    "d ${runnerHome}/.config 0755 backlogic-runner backlogic-runner -"
    "d ${runnerHome}/.config/git 0755 backlogic-runner backlogic-runner -"
    "L+ ${runnerHome}/.config/git/config - - - - ${aaronHome.xdg.configFile."git/config".source}"
    "L+ ${runnerHome}/.gitconfig - - - - ${runnerGitConfig}"
    "d ${runnerTokens} 0700 backlogic-runner backlogic-runner -"
  ];

  # Its sessions run inside the unit, so a switch never restarts it.
  # TMPDIR on tmpfs keeps the checks' fsyncs off the NVMe, and OOMPolicy=continue keeps the
  # other sessions running when one is killed for memory (backlogic's docs/decisions/runner.md).
  # Its weights and memory ceiling leave Bowerbird and the instance the box under pressure.
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
