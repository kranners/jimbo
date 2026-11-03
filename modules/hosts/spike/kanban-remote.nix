{
  config,
  lib,
  pkgs,
  ...
}:
let
  domain = "kanban.spike.cute.engineer";
  publicKey = import ./kanban-remote-key.nix;
  pilot = {
    address = "10.100.0.11";
    user = "aaronpierce";
  };
  state = "/var/lib/kanban-tunnel";
  board = "/run/kanban-tunnel/board.sock";

  # Devices that may reach the board, by WireGuard peer name, each still signing in through the device gate.
  viewers = [ "ipad" ];
  viewerAddresses = lib.concatMap (peer: peer.allowedIPs) (
    lib.filter (peer: lib.elem peer.name viewers) config.networking.wireguard.interfaces.wg0.peers
  );
in
{
  users.users.kanban-tunnel = {
    isSystemUser = true;
    group = "kanban-tunnel";
    home = state;
  };
  users.groups.kanban-tunnel = { };
  users.users.${config.services.caddy.user}.extraGroups = [ "kanban-tunnel" ];

  systemd.tmpfiles.rules = [ "d ${state} 0700 kanban-tunnel kanban-tunnel -" ];

  systemd.services.kanban-tunnel-key = {
    description = "Generate spike's key for the tunnel to pilot's kanban board";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "kanban-tunnel";
    };
    script = ''
      [ -f ${state}/id_ed25519 ] || ${pkgs.openssh}/bin/ssh-keygen -q -t ed25519 -N "" -C kanban-tunnel@spike -f ${state}/id_ed25519
    '';
  };

  # The board listens on pilot's loopback alone; this forwards that one port to a socket only Caddy may open,
  # and pilot's authorized_keys lets this key forward to 127.0.0.1:7420 and nothing else.
  systemd.services.kanban-tunnel = lib.mkIf (publicKey != null && viewerAddresses != [ ]) {
    description = "Forward pilot's kanban board to a socket for Caddy over WireGuard";
    wantedBy = [ "multi-user.target" ];
    requires = [ "kanban-tunnel-key.service" ];
    after = [
      "kanban-tunnel-key.service"
      "network-online.target"
    ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      User = "kanban-tunnel";
      Group = "kanban-tunnel";
      RuntimeDirectory = "kanban-tunnel";
      RuntimeDirectoryMode = "0750";
      ExecStart = lib.escapeShellArgs [
        "${pkgs.openssh}/bin/ssh"
        "-N"
        "-F"
        "none"
        "-i"
        "${state}/id_ed25519"
        "-o"
        "IdentitiesOnly=yes"
        "-o"
        "BatchMode=yes"
        "-o"
        "UserKnownHostsFile=${state}/known_hosts"
        "-o"
        "StrictHostKeyChecking=accept-new"
        "-o"
        "ExitOnForwardFailure=yes"
        "-o"
        "ServerAliveInterval=15"
        "-o"
        "ServerAliveCountMax=3"
        "-o"
        "StreamLocalBindUnlink=yes"
        "-o"
        "StreamLocalBindMask=0117"
        "-L"
        "${board}:127.0.0.1:7420"
        "${pilot.user}@${pilot.address}"
      ];
      Restart = "always";
      RestartSec = 30;
    };
  };

  services.caddy.virtualHosts.${domain} = lib.mkIf (viewerAddresses != [ ]) {
    logFormat = null;
    extraConfig = ''
      @outsider not remote_ip ${lib.concatStringsSep " " viewerAddresses}
      @foreignOrigin {
        header Origin *
        not header Origin https://${domain}
      }
      # The board trusts loopback callers on these, and through the tunnel every request comes from loopback.
      @machineOnly path /api/agent/* /api/butler/tools/* /api/docs/tools/* /api/hooks/* /api/runners /api/runners/* /runner.js
      route {
        abort @outsider
        abort @foreignOrigin
        respond @machineOnly 403
        reverse_proxy /.gate/* unix/${config.spike.deviceGate.socket}
        forward_auth unix/${config.spike.deviceGate.socket} {
          uri /.gate/verify
        }
        reverse_proxy unix/${board} {
          header_up Host 127.0.0.1:7420
          # The board checks writes against its own origin, which Caddy has checked against the site's above.
          header_up Origin http://127.0.0.1:7420
          # A tunnel header makes the board treat the request as remote, never as a local agent.
          header_up Cf-Connecting-Ip {remote_host}
          header_up -Authorization
          header_up -Cookie
        }
      }
    '';
  };
}
