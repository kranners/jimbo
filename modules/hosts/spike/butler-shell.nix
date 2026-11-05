{ config, pkgs, ... }:
let
  user = "butler-shell";
  home = "/var/lib/${user}";
  socket = "/run/butler-shell.sock";

  # The wrapper butler runs: it hands its stdin, the script, to the socket and
  # prints what comes back, so the script runs as butler-shell, never as butler.
  shell = pkgs.writeShellApplication {
    name = "shell";
    runtimeInputs = [ pkgs.socat ];
    text = ''
      [ $# -eq 0 ] || { echo "usage: shell <<'EOF' script EOF  (a bash script on stdin, no args)" >&2; exit 2; }
      exec socat -t 90 - UNIX-CONNECT:${socket}
    '';
  };

  # One instance per connection: reads the whole script, runs it with bash
  # and reports a nonzero exit status after its output.
  run = pkgs.writeShellScript "butler-shell-run" ''
    script=$(${pkgs.coreutils}/bin/cat)
    if [ -z "$script" ]; then
      echo "shell: the script on stdin is empty"
      exit 0
    fi
    cd ${home}
    ${pkgs.coreutils}/bin/timeout --kill-after=5 55 ${pkgs.bash}/bin/bash -c "$script" </dev/null 2>&1
    status=$?
    [ "$status" -eq 0 ] || echo "[exit status $status]"
  '';
in
{
  users.users.${user} = {
    isSystemUser = true;
    group = user;
    inherit home;
    createHome = true;
  };
  users.groups.${user} = { };

  systemd.sockets.butler-shell = {
    description = "Socket butler's shell command runs scripts through";
    wantedBy = [ "sockets.target" ];
    socketConfig = {
      ListenStream = socket;
      Accept = true;
      SocketUser = "root";
      SocketGroup = "butler";
      SocketMode = "0660";
      MaxConnections = 4;
    };
  };

  systemd.services."butler-shell@" = {
    description = "A script from butler's shell command, run as ${user}";
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
        wget
        openssh
        iputils
        iproute2
        dnsutils
        netcat-openbsd
        nmap
        wakeonlan
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

  butler.commands.shell = {
    package = shell;
    description = ''
      Run a bash script, given on stdin, on spike as the unprivileged user butler-shell, with no root, no sudo and none of your files or credentials, and print its output and any nonzero exit status; each run stops after 55 seconds. Takes no args.
      It has the network, so ssh, ping, curl, dig, nc, nmap and wakeonlan reach WireGuard, the LAN and the internet, and it reads the system journal with journalctl and service state with systemctl status. Its home, ${home}, persists between runs.
    '';
    stdin = true;
    # A conversation's and, through butler.nix's manifest, a scheduled run's alone: no voice request or call lane gets it.
    # Egress, so in a thread that has read private data or began as a voice request or board message the first script asks Aaron once for the `shell` area, and the rest run unasked.
    # A script the daemon's shell checker reads as sending, paying, deleting or changing security asks every time, showing what it matched.
    rules = [
      {
        match = [ ];
        lanes = [ "interactive" ];
        egress = true;
        grant = "shell";
        outcomes = "shell";
      }
    ];
    skill = ./butler-skills/shell;
  };
}
