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

  # A board restarting refuses connections for a few seconds, so Caddy holds each request and tries again for
  # up to 30 seconds, rather than answering 502 at once.
  retry = "lb_try_duration 30s\n    lb_try_interval 500ms";
  restarting = ''
    <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width">
    <meta http-equiv="refresh" content="5"><title>Kanban is restarting</title></head>
    <body style="font-family:system-ui;background:#111;color:#ddd;display:grid;place-items:center;height:100vh;margin:0">
    <p>The board is restarting, retrying in a few seconds…</p></body></html>
  '';

  # Devices that may reach the board, by WireGuard peer name, each still signing in through the device gate.
  viewers = [
    "pilot"
    "ipad"
    "phone"
    "phone-2"
    "piggys-MBP"
    "jimbo"
  ];
  # Machines whose kanban runner (modules/kanban-runner) checks in with the board's runner token; pilot's runs
  # only once its own board is unloaded, after the cutover to spike.
  runners = [
    "pilot"
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
  # A process takes its supplementary groups only when it starts, and a Caddyfile change only reloads Caddy, so
  # restart it whenever its groups change, or it keeps answering every request through the socket with a 502.
  systemd.services.caddy.restartTriggers = [
    (builtins.toJSON config.users.users.${config.services.caddy.user}.extraGroups)
  ];

  # The board listens on pilot's loopback alone, and butler's Mac key may forward to nothing there but Screen
  # Sharing, so each connection Caddy opens to this socket runs `nc` to the board's port over that key's ssh, the
  # route butler-board-relay already takes, sharing one master connection so only the first pays for the handshake.
  systemd.services.kanban-tunnel = lib.mkIf (viewerAddresses != [ ]) {
    description = "Carry Caddy's connections to pilot's kanban board over butler's ssh to pilot";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    # Once `kanban-hub cutover` moves the board to spike, kanban-bridge serves this socket from it instead, and
    # this unit stays defined but idle, for `kanban-hub rollback`.
    unitConfig.ConditionPathExists = "!${config.spike.kanban.hubMarker}";
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
    # The module's default access log, /var/log/caddy/access-${domain}.log, says what each request got.
    extraConfig = ''
      @outsider not remote_ip ${lib.concatStringsSep " " viewerAddresses}
      @foreignOrigin {
        header Origin *
        not header Origin https://${domain}
      }
      ${lib.optionalString (runnerAddresses != [ ]) ''
        # A runner's own calls, from a runner machine, carrying a bearer token and no browser Origin, skip the
        # device gate: the board checks its KANBAN_RUNNER_TOKEN on each, and these paths are all a runner needs,
        # its sessions' doc tools among them.
        @runner {
          remote_ip ${lib.concatStringsSep " " runnerAddresses}
          header Authorization "Bearer *"
          not header Origin *
          path_regexp ^/(runner\.js|api/runners/(register|docs/[a-z_]+|[a-z0-9-]+/(heartbeat|commands(/[A-Za-z0-9_-]+)?)))$
        }
      ''}
      # The board trusts loopback callers on these, and through the tunnel every request comes from loopback.
      @machineOnly path /api/agent/* /api/butler/tools/* /api/docs/tools/* /api/hooks/* /api/runners /api/runners/* /runner.js
      route {
        # A plain refusal rather than an abort, so a device left off the list says so instead of a reset stream.
        respond @outsider "This device may not reach the board." 403
        abort @foreignOrigin
        # Only the device gate names the device, which the board requires on a press of a Butler card's Approve:
        # a client's own header is dropped before anything else sees the request.
        request_header -X-Device-Gate-Device
        ${lib.optionalString (runnerAddresses != [ ]) ''
          reverse_proxy @runner unix/${board} {
            ${retry}
            header_up Host 127.0.0.1:7420
            header_up Cf-Connecting-Ip {remote_host}
            header_up -Cookie
          }
        ''}
        respond @machineOnly 403
        reverse_proxy /.gate/* unix/${config.spike.deviceGate.socket}
        forward_auth unix/${config.spike.deviceGate.socket} {
          uri /.gate/verify
          copy_headers X-Device-Gate-Device
        }
        reverse_proxy unix/${board} {
          ${retry}
          header_up Host 127.0.0.1:7420
          # The board checks writes against its own origin, which Caddy has checked against the site's above.
          header_up Origin http://127.0.0.1:7420
          # A tunnel header makes the board treat the request as remote, never as a local agent.
          header_up Cf-Connecting-Ip {remote_host}
          header_up -Authorization
          header_up -Cookie
        }
      }
      # While the board restarts and Caddy's retries above run out, a page that says so and reloads itself.
      handle_errors {
        @boardDown expression `{err.status_code} in [502, 503, 504]`
        handle @boardDown {
          header Retry-After 5
          header Cache-Control no-store
          header Content-Type "text/html; charset=utf-8"
          respond `${restarting}` 503
        }
      }
    '';
  };
}
