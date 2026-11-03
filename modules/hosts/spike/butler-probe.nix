{
  config,
  pkgs,
  lib,
  ...
}:
let
  inherit (lib) mkOption types;
  cfg = config.butler.selfFixProbe;

  user = "butler-probe";
  home = "/var/lib/${user}";
  socket = "/run/butler-probe.sock";
  state = "/var/lib/butler-probe-runner";
  masterKey = "/var/lib/secrets/butler-probe-key";
  memoryDeployKey = "/var/lib/secrets/butler-memory-deploy-key";
  selfFix = "${config.users.users.butler.home}/self-fix";

  # Loopback ports the sandbox may reach: metrics, dashboards, Home Assistant's and backlogic's
  # APIs, which still want their own tokens, and the Wyoming speech servers. Every other local
  # service, Bowerbird's VNC displays and butler's browser among them, is refused.
  loopbackPorts = [
    9090
    3001
    8123
    4200
    10200
    10300
  ];
  privateV4 = [
    "10.0.0.0/8"
    "172.16.0.0/12"
    "192.168.0.0/16"
    "169.254.0.0/16"
    "100.64.0.0/10"
  ];
  privateV6 = [
    "fc00::/7"
    "fe80::/10"
  ];

  # Holds butler-probe to DNS, the internet and the loopback ports above, so a script reaches
  # nothing on the LAN or WireGuard: not framer, the Macs, the router or any peer.
  outputChain = iptables: private: ''
    ${iptables} -D OUTPUT -m owner --uid-owner ${user} -j butler-probe-out 2> /dev/null || true
    ${iptables} -F butler-probe-out 2> /dev/null || true
    ${iptables} -X butler-probe-out 2> /dev/null || true
    ${iptables} -N butler-probe-out
    ${iptables} -A butler-probe-out -p udp --dport 53 -j RETURN
    ${iptables} -A butler-probe-out -p tcp --dport 53 -j RETURN
    ${lib.concatMapStrings (port: ''
      ${iptables} -A butler-probe-out -o lo -p tcp --dport ${toString port} -j RETURN
    '') loopbackPorts}
    ${iptables} -A butler-probe-out -o lo -j REJECT
    ${lib.concatMapStrings (net: ''
      ${iptables} -A butler-probe-out -d ${net} -j REJECT
    '') private}
    ${iptables} -I OUTPUT -m owner --uid-owner ${user} -j butler-probe-out
  '';

  # One instance per request: the same runner as butler's shell, as butler-probe.
  run = pkgs.writeShellScript "butler-probe-run" ''
    script=$(${pkgs.coreutils}/bin/cat)
    cd ${home}
    ${pkgs.coreutils}/bin/timeout --kill-after=5 55 ${pkgs.bash}/bin/bash -c "$script" </dev/null 2>&1
    status=$?
    [ "$status" -eq 0 ] || echo "[exit status $status]"
  '';

  runner = pkgs.writeShellApplication {
    name = "butler-probe-runner";
    runtimeInputs = [
      pkgs.git
      pkgs.openssh
      pkgs.socat
      pkgs.python3
    ];
    text = ''
      export PROBE_STATE=${state} PROBE_SELF_FIX=${selfFix} PROBE_KEY_FILE="$CREDENTIALS_DIRECTORY/probe-key"
      export GIT_SSH_COMMAND="ssh -i $CREDENTIALS_DIRECTORY/memory-deploy-key -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=${state}/known_hosts"
      exec python3 -I ${./butler-probe/runner.py} poll
    '';
  };

  # Printed after Aaron's request in each self-fix brief, with that fix's own key.
  brief = pkgs.writeShellApplication {
    name = "butler-probe-brief";
    runtimeInputs = [ pkgs.python3 ];
    text = ''
      id=$1
      key=$(PROBE_KEY_FILE=${masterKey} python3 -I ${./butler-probe/runner.py} key "$id") || exit 0
      cat <<EOF


      Spike probe for this self-fix: you can run checks on spike itself.
      Call add_repo for kranners/butler-memory with access "push", then run once, from the jimbo checkout: modules/hosts/spike/butler-probe/spike-probe init $id $key
      That key is this fix's alone and stops working when this session ends; never print, commit or repeat it.
      Then \`modules/hosts/spike/butler-probe/spike-probe <<'SCRIPT' ... SCRIPT\` runs a bash script on spike as the unprivileged user butler-probe and prints its output within about a minute, each run stopping after 55 seconds, at most 30 an hour.
      It reads the system journal and systemctl status, has curl, git, jq and python3 and the internet, reaches on loopback only Prometheus :9090, Grafana :3001, Home Assistant :8123, backlogic :4200 and the Wyoming speech servers :10300 and :10200, and nothing on the LAN or WireGuard.
      It has no root, no sudo and none of butler's files, memory or credentials, so a butler command needing a credential cannot run there; any other can, from its store path in the manifest that DISCORD_COMMANDS_FILE in \`systemctl show butler -p Environment\` names.
      Use it to verify your work before you report done: once your change lands, wait for spike to deploy it (\`journalctl -u jimbo-switch\` or \`-u butler-pull\`, \`readlink /run/current-system\`), check the units you changed are active and their logs clean, and run what you built where it can run.
      Say plainly in your summary what you checked on spike and what you could not.
      EOF
    '';
  };
in
{
  options.butler.selfFixProbe = {
    enable = mkOption {
      description = "Whether butler's self-fix cloud sessions may run sandboxed checks on spike, through signed requests spike pulls from butler-memory.";
      type = types.bool;
      default = true;
    };
    brief = mkOption {
      description = "The command printing a self-fix brief's probe paragraph for an id, or null while the probe is off.";
      type = types.nullOr types.package;
      default = null;
      internal = true;
    };
  };

  config = lib.mkIf cfg.enable {
    butler.selfFixProbe.brief = brief;

    users.users.${user} = {
      isSystemUser = true;
      group = user;
      inherit home;
      createHome = true;
    };
    users.groups.${user} = { };

    systemd.sockets.butler-probe = {
      description = "Socket the self-fix probe runs its sandboxed scripts through";
      wantedBy = [ "sockets.target" ];
      socketConfig = {
        ListenStream = socket;
        Accept = true;
        SocketUser = "root";
        SocketGroup = "root";
        SocketMode = "0600";
        MaxConnections = 2;
      };
    };

    systemd.services."butler-probe@" = {
      description = "A self-fix session's check, run as ${user}";
      path =
        (with pkgs; [
          bash
          coreutils
          findutils
          gnugrep
          gnused
          gawk
          diffutils
          file
          jq
          curl
          iputils
          iproute2
          dnsutils
          procps
          git
          python3
        ])
        ++ [ config.systemd.package ];
      environment = {
        HOME = home;
        LANG = "C.UTF-8";
      };
      serviceConfig = {
        User = user;
        Group = user;
        SupplementaryGroups = [ "systemd-journal" ];
        StandardInput = "socket";
        StandardOutput = "socket";
        StandardError = "socket";
        ExecStart = run;
        RuntimeMaxSec = 90;
        Nice = 10;
        CPUWeight = 20;
        IOWeight = 20;
        MemoryHigh = "768M";
        MemoryMax = "1G";
        MemorySwapMax = "256M";
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectProc = "invisible";
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        TemporaryFileSystem = [ "/var/lib" ];
        BindPaths = [ home ];
        InaccessiblePaths = [ "-/srv" ];
      };
    };

    networking.firewall.extraCommands =
      outputChain "iptables" privateV4 + outputChain "ip6tables" privateV6;
    networking.firewall.extraStopCommands = ''
      iptables -D OUTPUT -m owner --uid-owner ${user} -j butler-probe-out 2> /dev/null || true
      ip6tables -D OUTPUT -m owner --uid-owner ${user} -j butler-probe-out 2> /dev/null || true
    '';

    # The master key never leaves spike; each fix gets a key derived from it and its id.
    systemd.services.butler-probe-key = {
      description = "Generate the self-fix probe's master key once";
      unitConfig.ConditionPathExists = "!${masterKey}";
      serviceConfig.Type = "oneshot";
      script = ''
        umask 077
        mkdir -p /var/lib/secrets
        ${pkgs.coreutils}/bin/od -An -tx1 -N32 /dev/urandom | ${pkgs.coreutils}/bin/tr -d ' \n' > ${masterKey}.tmp
        mv ${masterKey}.tmp ${masterKey}
      '';
    };
    systemd.services.butler-self-fix = {
      wants = [ "butler-probe-key.service" ];
      after = [ "butler-probe-key.service" ];
    };

    systemd.services.butler-probe-runner = {
      description = "Run the checks live self-fix sessions left on their spike-probe branches, and push the output back";
      wants = [
        "network-online.target"
        "butler-probe-key.service"
      ];
      after = [
        "network-online.target"
        "butler-probe-key.service"
      ];
      unitConfig.ConditionPathExists = memoryDeployKey;
      serviceConfig = {
        Type = "oneshot";
        ExecStart = lib.getExe runner;
        LoadCredential = [
          "probe-key:${masterKey}"
          "memory-deploy-key:${memoryDeployKey}"
        ];
        StateDirectory = "butler-probe-runner";
        StateDirectoryMode = "0700";
        TimeoutStartSec = "10min";
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
      };
    };

    systemd.timers.butler-probe-runner = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "1min";
        OnUnitInactiveSec = "20s";
        AccuracySec = "1s";
      };
    };

    # Keeps a month of requests and results; the log of every request stays.
    systemd.tmpfiles.rules = [
      "e ${state}/results - - - 30d"
      "e ${home} - - - 2d"
    ];
  };
}
