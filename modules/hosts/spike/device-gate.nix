{
  config,
  lib,
  pkgs,
  ...
}:
let
  passwordFile = "/var/lib/secrets/device-gate-password";
  gate = pkgs.writers.writePython3Bin "device-gate" {
    flakeIgnore = [ "E501" ];
  } (builtins.readFile ./device-gate/gate.py);

  # Asks for the password twice, writes its scrypt hash for the gate and signs every device out.
  setPassword = pkgs.writeShellApplication {
    name = "device-gate-password";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      if [ "$(id -u)" != 0 ]; then
        echo "run it with sudo" >&2
        exit 1
      fi
      read -rsp "New password for spike's device gate: " first
      echo
      read -rsp "Again: " second
      echo
      if [ "$first" != "$second" ] || [ "''${#first}" -lt 12 ]; then
        echo "the passwords differ or are under 12 characters; nothing changed" >&2
        exit 1
      fi
      umask 077
      mkdir -p /var/lib/secrets
      printf '%s\n' "$first" | ${lib.getExe gate} hash > ${passwordFile}.new
      mv ${passwordFile}.new ${passwordFile}
      rm -f /var/lib/device-gate/session-key
      systemctl restart device-gate.service
      echo "set; every device must sign in again"
    '';
  };
in
{
  options.spike.deviceGate.socket = lib.mkOption {
    type = lib.types.str;
    default = "/run/device-gate.sock";
    readOnly = true;
    description = "The socket Caddy's forward_auth and /.gate/* reach the device gate on.";
  };

  config = {
    environment.systemPackages = [ setPassword ];

    # The iPad reaches the life explorer and money dashboard too, only once it has signed in here.
    butler.index.explorer = {
      gatedDevices = [ "ipad" ];
      gateSocket = config.spike.deviceGate.socket;
    };

    users.users.device-gate = {
      isSystemUser = true;
      group = "device-gate";
    };
    users.groups.device-gate = { };

    # Only Caddy may open it, so no local user can try passwords against it.
    systemd.sockets.device-gate = {
      wantedBy = [ "sockets.target" ];
      # Until the password is set there is no socket, so every gated site answers 502 at once.
      unitConfig.ConditionPathExists = passwordFile;
      socketConfig = {
        ListenStream = config.spike.deviceGate.socket;
        SocketGroup = config.services.caddy.group;
        SocketMode = "0660";
      };
    };

    systemd.services.device-gate = {
      description = "Sign devices in before Caddy lets them through to sites gated by device";
      requires = [ "device-gate.socket" ];
      unitConfig.ConditionPathExists = passwordFile;
      serviceConfig = {
        ExecStart = lib.getExe gate;
        User = "device-gate";
        Group = "device-gate";
        StateDirectory = "device-gate";
        StateDirectoryMode = "0700";
        LoadCredential = [ "password:${passwordFile}" ];
        Restart = "on-failure";
        MemoryMax = "256M";
        IPAddressDeny = "any";
        RestrictAddressFamilies = [ "AF_UNIX" ];
        PrivateDevices = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        NoNewPrivileges = true;
        CapabilityBoundingSet = "";
        SystemCallFilter = "@system-service";
      };
    };
  };
}
