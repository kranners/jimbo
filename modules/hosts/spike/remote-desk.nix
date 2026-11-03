{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkOption types;

  cfg = config.remoteDesk;

  domain = "desk.spike.cute.engineer";
  state = "/var/lib/remote-desk";
  runtime = "/run/remote-desk";

  peers = config.networking.wireguard.interfaces.wg0.peers;
  peer = name: lib.findFirst (peer: peer.name == name) null peers;
  addressOf = name: lib.removeSuffix "/32" (lib.head (peer name).allowedIPs);
  # Aaron's own devices alone, and an `ipad` peer whenever ./wireguard.nix has one.
  viewerAddresses = lib.concatMap (peer: peer.allowedIPs) (
    lib.filter (peer: lib.elem peer.name cfg.viewers) peers
  );

  hosts = {
    piggys-MBP = {
      label = "piggys-MBP";
      systems = [
        {
          os = "macos";
          address = addressOf "piggys-MBP";
          user = "aaron";
        }
      ];
    };
    pilot = {
      label = "pilot";
      note = "The work Mac, managed by its employer: keep-awake stays off here, so it locks and sleeps as usual.";
      systems = [
        {
          os = "macos";
          address = addressOf "pilot";
          user = "aaronpierce";
        }
      ];
    };
    jimbo = {
      label = "jimbo PC";
      note = "Dual boot: whichever of NixOS or Windows is up answers. Wi-Fi only, so asleep or off it cannot be woken from here.";
      systems =
        lib.optional (peer "jimbo" != null) {
          os = "linux";
          address = addressOf "jimbo";
          user = "aaron";
        }
        ++ [
          {
            os = "windows";
            address = addressOf "windows";
            user = "aaron";
          }
        ];
    };
  };

  web = pkgs.runCommand "remote-desk-web" { nativeBuildInputs = [ pkgs.librsvg ]; } ''
    mkdir $out
    cp ${./remote-desk/web}/* $out/
    for size in 180 192 512; do
      rsvg-convert -w $size -h $size ${./remote-desk/web/icon.svg} -o $out/icon-$size.png
    done
  '';

  settings = {
    inherit domain state runtime;
    user = "remote-desk";
    hosts = lib.filterAttrs (name: _: lib.elem name cfg.hosts) hosts;
    inherit (cfg) idleMinutes sessionHours;
    ssh = lib.getExe pkgs.openssh;
    ss = "${pkgs.iproute2}/bin/ss";
    web = "${web}";
    novnc = "${pkgs.novnc}/share/webapps/novnc";
  };

  remote-desk =
    pkgs.writers.writePython3Bin "remote-desk"
      {
        libraries = [ pkgs.python3Packages.aiohttp ];
        flakeIgnore = [ "E501" ];
      }
      (
        builtins.replaceStrings [ "@config@" ] [ (builtins.toJSON settings) ] (
          builtins.readFile ./remote-desk/server.py
        )
      );
in
{
  options.remoteDesk = {
    enable = mkOption {
      description = "Whether spike serves Aaron's web remote desktop, a launcher and noVNC viewer for his machines, at https://${domain}.";
      type = types.bool;
      default = true;
    };
    viewers = mkOption {
      description = "The WireGuard peers that may reach the gateway at all; each still signs in through spike's device gate.";
      type = types.listOf types.str;
      default = [
        "ipad"
        "piggys-MBP"
        "phone"
        "phone-2"
      ];
    };
    hosts = mkOption {
      description = "The machines the gateway offers, of piggys-MBP, pilot and jimbo.";
      type = types.listOf (
        types.enum [
          "piggys-MBP"
          "pilot"
          "jimbo"
        ]
      );
      default = [
        "piggys-MBP"
        "pilot"
        "jimbo"
      ];
    };
    idleMinutes = mkOption {
      description = "Minutes without a touch or key after which a screen closes and a login ends.";
      type = types.ints.positive;
      default = 15;
    };
    sessionHours = mkOption {
      description = "Hours a device gate sign-in lasts here, and after which a session ends however active it is.";
      type = types.ints.positive;
      default = 12;
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.remote-desk = {
      isSystemUser = true;
      group = "remote-desk";
      home = state;
    };
    users.groups.remote-desk = { };
    # Caddy reaches the gateway's unix socket through the group; the tunnels' sockets sit in a 0700 directory below.
    users.users.${config.services.caddy.user}.extraGroups = [ "remote-desk" ];

    environment.systemPackages = [ remote-desk ];

    # The device gate is the one login, as for the board and the life explorer: it signs a device in here for
    # sessionHours, and signing a device out there ends its sessions and screens here too.
    spike.deviceGate = {
      lifetimes.${domain} = cfg.sessionHours * 3600;
      revokeHooks = [ "${lib.getExe remote-desk} revoke" ];
    };

    systemd.services.remote-desk = {
      description = "Aaron's web remote desktop: a launcher and noVNC viewer behind Caddy, opening each screen through its own ssh tunnel";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      path = [ pkgs.openssh ];
      serviceConfig = {
        User = "remote-desk";
        Group = "remote-desk";
        StateDirectory = "remote-desk";
        StateDirectoryMode = "0700";
        RuntimeDirectory = "remote-desk";
        RuntimeDirectoryMode = "0750";
        UMask = "0077";
        WorkingDirectory = state;
        # The gateway's own key, which every machine authorizes only to tunnel to its VNC and report its lock state.
        ExecStartPre = pkgs.writeShellScript "remote-desk-key" ''
          if [ ! -s ${state}/ssh/id_ed25519 ]; then
            mkdir -p -m 700 ${state}/ssh
            ssh-keygen -q -t ed25519 -N "" -C remote-desk@spike -f ${state}/ssh/id_ed25519
          fi
        '';
        ExecStart = "${lib.getExe remote-desk} serve";
        Restart = "always";
        RestartSec = 5;
        MemoryMax = "256M";
        NoNewPrivileges = true;
        ProtectHome = true;
        ProtectSystem = "strict";
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictAddressFamilies = [
          "AF_UNIX"
          "AF_INET"
          "AF_INET6"
          "AF_NETLINK"
        ];
        LockPersonality = true;
        CapabilityBoundingSet = "";
      };
    };

    services.caddy.virtualHosts.${domain}.extraConfig = ''
      @outsider not remote_ip ${lib.concatStringsSep " " viewerAddresses}
      @foreignOrigin {
        header Origin *
        not header Origin https://${domain}
      }
      route {
        abort @outsider
        abort @foreignOrigin
        # Only the device gate names the device: a client's own header is dropped before the gate is asked.
        request_header -X-Device-Gate-Device
        reverse_proxy /.gate/* unix/${config.spike.deviceGate.socket}
        forward_auth unix/${config.spike.deviceGate.socket} {
          uri /.gate/verify
          copy_headers X-Device-Gate-Device
        }
        reverse_proxy unix/${runtime}/http.sock {
          header_up X-Remote-Desk-Client {remote_host}
        }
      }
    '';
  };
}
