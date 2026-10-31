{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkOption types;
  inherit (config.users.users.butler-browser) home;

  cfg = config.butler.browser;

  domain = "browser.spike.cute.engineer";
  profile = "${home}/profile";
  activity = "/run/butler-browser";
  display = ":50";
  cdpPort = 9222;
  vncPort = 5950;
  panelVncPort = 5951;
  viewPort = 6081;
  panelPort = 6082;
  addressesOf =
    names:
    lib.concatMap (peer: peer.allowedIPs) (
      lib.filter (peer: lib.elem peer.name names) config.networking.wireguard.interfaces.wg0.peers
    );
  viewerAddresses = addressesOf [
    "piggys-MBP"
    "phone"
    "phone-2"
  ];
  panelAddresses = addressesOf [ "framer" ];

  tools = [
    "browser_snapshot"
    "browser_find"
    "browser_console_messages"
    "browser_network_requests"
    "browser_network_request"
    "browser_wait_for"
    "browser_navigate"
    "browser_navigate_back"
    "browser_click"
    "browser_type"
    "browser_fill_form"
    "browser_press_key"
    "browser_select_option"
    "browser_drag"
    "browser_hover"
    "browser_handle_dialog"
    "browser_tabs"
    "browser_resize"
    "browser_emulate_media"
    "browser_close"
  ];
  qualified = map (tool: "mcp__browser__${tool}");

  mcpConfig = pkgs.writeText "butler-mcp.json" (
    builtins.toJSON {
      mcpServers.browser = {
        command = lib.getExe pkgs.playwright-mcp;
        args = [
          "--cdp-endpoint"
          "http://127.0.0.1:${toString cdpPort}"
          "--snapshot-mode"
          "none"
          "--console-level"
          "error"
          "--idle-timeout"
          "60000"
          "--no-webmcp"
          "--output-dir"
          "/tmp/playwright-mcp"
        ];
        env.PLAYWRIGHT_MCP_USER_DATA_DIR = profile;
      };
      allowedTools = qualified tools;
      safe = [ "mcp__browser__*" ];
    }
  );

  butler-browser = pkgs.writeShellApplication {
    name = "butler-browser";
    runtimeInputs = [
      pkgs.xorg-server
      pkgs.xdpyinfo
      pkgs.x11vnc
      pkgs.chromium
    ];
    text = ''
      Xvfb ${display} -screen 0 1280x800x24 -nolisten tcp -nolisten local &
      xvfb_pid=$!
      until xdpyinfo -display ${display} > /dev/null 2>&1; do sleep 0.2; done

      x11vnc -display ${display} -listen 127.0.0.1 -noipv6 -rfbport ${toString vncPort} -nopw -forever -shared -quiet &
      vnc_pid=$!
      x11vnc -display ${display} -listen 127.0.0.1 -noipv6 -rfbport ${toString panelVncPort} -viewonly -nopw -forever -shared -quiet &
      panel_vnc_pid=$!
      trap 'kill "$xvfb_pid" "$vnc_pid" "$panel_vnc_pid"' EXIT

      DISPLAY=${display} chromium \
        --user-data-dir=${profile} \
        --remote-debugging-address=127.0.0.1 \
        --remote-debugging-port=${toString cdpPort} \
        --password-store=basic \
        --no-first-run \
        --no-default-browser-check \
        --hide-crash-restore-bubble \
        --window-position=0,0 \
        --window-size=1280,800
    '';
  };

  bridge = listen: vnc: description: {
    inherit description;
    wantedBy = [ "multi-user.target" ];
    after = [ "butler-browser.service" ];
    serviceConfig = {
      User = "butler-browser";
      ExecStart = "${lib.getExe pkgs.python3Packages.websockify} --web ${pkgs.novnc}/share/webapps/novnc 127.0.0.1:${toString listen} 127.0.0.1:${toString vnc}";
      Restart = "always";
      RestartSec = 5;
      ProtectHome = true;
      ProtectSystem = "strict";
      PrivateTmp = true;
    };
  };

  butler-browser-activity = pkgs.writeShellApplication {
    name = "butler-browser-activity";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.iproute2
    ];
    text = ''
      shown=""
      while true; do
        if [ -n "$(ss -Htn state established '( dport = :${toString cdpPort} )')" ]; then
          active=1
        else
          active=0
        fi
        if [ "$active" != "$shown" ]; then
          printf '%s\n' "$active" > ${activity}/active.new
          mv ${activity}/active.new ${activity}/active
          shown=$active
        fi
        sleep 2
      done
    '';
  };

  guards = [
    {
      port = cdpPort;
      user = "butler";
    }
    {
      port = vncPort;
      user = "butler-browser";
    }
    {
      port = panelVncPort;
      user = "butler-browser";
    }
    {
      port = viewPort;
      user = "caddy";
    }
    {
      port = panelPort;
      user = "caddy";
    }
  ];

  loopbackChain = iptables: ''
    ${iptables} -D OUTPUT -o lo -j butler-browser-loopback 2> /dev/null || true
    ${iptables} -F butler-browser-loopback 2> /dev/null || true
    ${iptables} -X butler-browser-loopback 2> /dev/null || true
    ${iptables} -N butler-browser-loopback
    ${lib.concatMapStrings (guard: ''
      ${iptables} -A butler-browser-loopback -p tcp --dport ${toString guard.port} -m owner --uid-owner ${guard.user} -j RETURN
      ${iptables} -A butler-browser-loopback -p tcp --dport ${toString guard.port} -j REJECT --reject-with tcp-reset
    '') guards}
    ${iptables} -I OUTPUT -o lo -j butler-browser-loopback
  '';
in
{
  options.butler.browser.enable = mkOption {
    description = "Whether butler drives its own Chromium on spike through Playwright MCP, logged in by hand over noVNC.";
    type = types.bool;
    default = true;
  };

  config = lib.mkIf cfg.enable {
    users.users.butler-browser = {
      isSystemUser = true;
      group = "butler-browser";
      home = "/var/lib/butler-browser";
    };
    users.groups.butler-browser = { };

    systemd.services.butler-browser = {
      description = "Butler's Chromium on a virtual display, driven over CDP on loopback";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      serviceConfig = {
        User = "butler-browser";
        StateDirectory = "butler-browser";
        StateDirectoryMode = "0700";
        WorkingDirectory = home;
        ExecStart = lib.getExe butler-browser;
        Restart = "always";
        RestartSec = 5;
        MemoryHigh = "1200M";
        MemoryMax = "1536M";
        OOMPolicy = "continue";
        CPUQuota = "200%";
        NoNewPrivileges = true;
        ProtectHome = true;
        ProtectSystem = "strict";
        PrivateTmp = true;
      };
    };

    systemd.services.butler-browser-view =
      bridge viewPort vncPort
        "noVNC bridge to butler's Chromium, for logging it in by hand";

    systemd.services.butler-browser-panel =
      bridge panelPort panelVncPort
        "View-only noVNC bridge to butler's Chromium, for framer's panel";

    systemd.services.butler-browser-activity = {
      description = "Publish whether butler is driving its Chromium, for framer's panel";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        User = "butler-browser";
        RuntimeDirectory = "butler-browser";
        RuntimeDirectoryMode = "0755";
        ExecStart = lib.getExe butler-browser-activity;
        Restart = "always";
        RestartSec = 5;
        ProtectHome = true;
        ProtectSystem = "strict";
        PrivateTmp = true;
      };
    };

    systemd.services.butler.environment.DISCORD_MCP_CONFIG = "${mcpConfig}";

    systemd.tmpfiles.rules = [
      "L+ ${config.users.users.butler.home}/.claude/skills/browser - - - - ${./butler-skills/browser}"
    ];

    networking.firewall.extraCommands = loopbackChain "iptables" + loopbackChain "ip6tables";

    networking.firewall.extraStopCommands = ''
      iptables -D OUTPUT -o lo -j butler-browser-loopback 2> /dev/null || true
      ip6tables -D OUTPUT -o lo -j butler-browser-loopback 2> /dev/null || true
    '';

    services.caddy.virtualHosts.${domain}.extraConfig = ''
      @outsider not remote_ip ${lib.concatStringsSep " " (viewerAddresses ++ panelAddresses)}
      @foreignOrigin {
        header Origin *
        not header Origin https://${domain}
      }
      @panel remote_ip ${lib.concatStringsSep " " panelAddresses}
      route {
        abort @outsider
        abort @foreignOrigin
        handle /active {
          root * ${activity}
          file_server
        }
        handle @panel {
          reverse_proxy 127.0.0.1:${toString panelPort}
        }
        handle {
          reverse_proxy 127.0.0.1:${toString viewPort}
        }
      }
    '';
  };
}
