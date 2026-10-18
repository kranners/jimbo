{
  inputs,
  lib,
  pkgs,
  ...
}:
let
  home = "/home/aaron";
  checkout = "${home}/workspace/jimbo";
  runnerCheckout = "${home}/workspace/backlogic--service";
  runnerTmp = "/run/backlogic-runner-tmp";

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

  # Its sessions run inside the unit, so a switch never restarts it.
  # TMPDIR on tmpfs keeps the checks' fsyncs off the NVMe, on a tmpfs of its own outside /dev,
  # where Deno grants a named --allow-read or --allow-write nothing, and OOMPolicy=continue keeps
  # the other sessions running when one is killed for memory (backlogic's docs/decisions/runner.md).
  fileSystems.${runnerTmp} = {
    device = "tmpfs";
    fsType = "tmpfs";
    options = [
      "size=50%"
      "mode=0700"
      "uid=1000"
      "gid=100"
      "nosuid"
      "nodev"
    ];
  };

  systemd.services.backlogic-runner-aaron = {
    description = "backlogic runner launching sessions on Aaron's instance";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [
      "network-online.target"
      "backlogic-aaron.service"
    ];
    restartIfChanged = false;
    unitConfig.RequiresMountsFor = runnerTmp;
    path = [
      "/run/wrappers"
      "/run/current-system/sw"
    ];
    environment = {
      TMPDIR = runnerTmp;
      XDG_RUNTIME_DIR = "/run/user/1000";
    };
    serviceConfig = {
      User = "aaron";
      WorkingDirectory = runnerCheckout;
      ExecStart = "${runnerCheckout}/bin/backlogic-runner --url http://127.0.0.1:4200";
      OOMPolicy = "continue";
      Restart = "always";
      RestartSec = 30;
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
