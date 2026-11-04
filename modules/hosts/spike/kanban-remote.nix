{
  config,
  lib,
  pkgs,
  ...
}:
let
  domain = "kanban.spike.cute.engineer";
  pilot = {
    address = "10.100.0.11";
    user = "aaronpierce";
  };
  board = "/run/kanban-tunnel/board.sock";
  # One connection to the board: stdin and stdout are the bytes Caddy sends and receives.
  connect = pkgs.writeShellScript "kanban-tunnel-connect" ''
    exec ${pkgs.openssh}/bin/ssh -F none \
      -i "$CREDENTIALS_DIRECTORY/butler-mac-key" \
      -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=5 \
      -o UserKnownHostsFile=/var/lib/butler-kanban/known_hosts -o StrictHostKeyChecking=accept-new \
      -o ControlMaster=auto -o ControlPath=/run/kanban-tunnel/ssh-%C -o ControlPersist=300 \
      -o ServerAliveInterval=15 -o ServerAliveCountMax=3 \
      ${pilot.user}@${pilot.address} exec /usr/bin/nc 127.0.0.1 7420
  '';

  # Devices that may reach the board, by WireGuard peer name, each still signing in through the device gate.
  viewers = [
    "ipad"
    "phone"
    "phone-2"
    "piggys-MBP"
    "jimbo"
  ];
  # Machines whose kanban runner (modules/kanban-runner) checks in with the board's runner token.
  runners = [
    "piggys-MBP"
    "jimbo"
  ];
  addressesOf =
    names:
    lib.concatMap (peer: peer.allowedIPs) (
      lib.filter (peer: lib.elem peer.name names) config.networking.wireguard.interfaces.wg0.peers
    );
  viewerAddresses = addressesOf viewers;
  runnerAddresses = addressesOf runners;
in
{
  users.groups.kanban-tunnel = { };
  users.users.${config.services.caddy.user}.extraGroups = [ "kanban-tunnel" ];

  # The board listens on pilot's loopback alone, and butler's Mac key may forward to nothing there but Screen
  # Sharing, so each connection Caddy opens to this socket runs `nc` to the board's port over that key's ssh, the
  # route butler-board-relay already takes, sharing one master connection so only the first pays for the handshake.
  systemd.services.kanban-tunnel = lib.mkIf (viewerAddresses != [ ]) {
    description = "Carry Caddy's connections to pilot's kanban board over butler's ssh to pilot";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    serviceConfig = {
      Group = "kanban-tunnel";
      RuntimeDirectory = "kanban-tunnel";
      RuntimeDirectoryMode = "0750";
      StateDirectory = "butler-kanban";
      LoadCredential = "butler-mac-key:/var/lib/secrets/butler-mac-key";
      ExecStart = lib.escapeShellArgs [
        "${pkgs.socat}/bin/socat"
        "UNIX-LISTEN:${board},fork,unlink-early,mode=0660,group=kanban-tunnel"
        "EXEC:${connect}"
      ];
      Restart = "always";
      RestartSec = 10;
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
      ${lib.optionalString (runnerAddresses != [ ]) ''
        # A runner's own calls, from a runner machine, carrying a bearer token and no browser Origin, skip the
        # device gate: the board checks its KANBAN_RUNNER_TOKEN on each, and these paths are all a runner needs.
        @runner {
          remote_ip ${lib.concatStringsSep " " runnerAddresses}
          header Authorization "Bearer *"
          not header Origin *
          path_regexp ^/(runner\.js|api/runners/(register|[a-z0-9-]+/(heartbeat|commands(/[A-Za-z0-9_-]+)?)))$
        }
      ''}
      # The board trusts loopback callers on these, and through the tunnel every request comes from loopback.
      @machineOnly path /api/agent/* /api/butler/tools/* /api/docs/tools/* /api/hooks/* /api/runners /api/runners/* /runner.js
      route {
        abort @outsider
        abort @foreignOrigin
        ${lib.optionalString (runnerAddresses != [ ]) ''
          reverse_proxy @runner unix/${board} {
            header_up Host 127.0.0.1:7420
            header_up Cf-Connecting-Ip {remote_host}
            header_up -Cookie
          }
        ''}
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
