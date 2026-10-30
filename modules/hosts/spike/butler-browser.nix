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
  viewPort = 6081;
  viewers = [
    "piggys-MBP"
    "phone"
    "phone-2"
    "framer"
  ];
  viewerAddresses = lib.concatMap (peer: peer.allowedIPs) (
    lib.filter (peer: lib.elem peer.name viewers) config.networking.wireguard.interfaces.wg0.peers
  );

  readTools = [
    "browser_snapshot"
    "browser_find"
    "browser_console_messages"
    "browser_network_requests"
    "browser_network_request"
    "browser_wait_for"
  ];
  actionTools = [
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
  ];
  quietTools = [
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
      allowedTools = qualified (readTools ++ actionTools ++ quietTools);
      taints = qualified readTools;
      egress = qualified actionTools;
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
      trap 'kill "$xvfb_pid" "$vnc_pid"' EXIT

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

  butler-browser-view = pkgs.writeShellApplication {
    name = "butler-browser-view";
    runtimeInputs = [ pkgs.python3Packages.websockify ];
    text = ''
      exec websockify --web ${pkgs.novnc}/share/webapps/novnc 127.0.0.1:${toString viewPort} 127.0.0.1:${toString vncPort}
    '';
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

  loopbackGuard = port: user: ''
    iptables -A butler-browser-loopback -p tcp --dport ${toString port} -m owner --uid-owner ${user} -j RETURN
    iptables -A butler-browser-loopback -p tcp --dport ${toString port} -j REJECT --reject-with tcp-reset
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
        MemoryMax = "1536M";
        ProtectHome = true;
        ProtectSystem = "strict";
        PrivateTmp = true;
      };
    };

    systemd.services.butler-browser-view = {
      description = "noVNC bridge to butler's Chromium, for logging it in by hand";
      wantedBy = [ "multi-user.target" ];
      after = [ "butler-browser.service" ];
      serviceConfig = {
        User = "butler-browser";
        ExecStart = lib.getExe butler-browser-view;
        Restart = "always";
        RestartSec = 5;
        ProtectHome = true;
        ProtectSystem = "strict";
        PrivateTmp = true;
      };
    };

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

    networking.firewall.extraCommands = ''
      iptables -D OUTPUT -o lo -j butler-browser-loopback 2> /dev/null || true
      iptables -F butler-browser-loopback 2> /dev/null || true
      iptables -X butler-browser-loopback 2> /dev/null || true
      iptables -N butler-browser-loopback
      ${loopbackGuard cdpPort "butler"}
      ${loopbackGuard vncPort "butler-browser"}
      ${loopbackGuard viewPort "caddy"}
      iptables -I OUTPUT -o lo -j butler-browser-loopback
    '';

    networking.firewall.extraStopCommands = ''
      iptables -D OUTPUT -o lo -j butler-browser-loopback 2> /dev/null || true
    '';

    services.caddy.virtualHosts.${domain}.extraConfig = ''
      @outsider not remote_ip ${lib.concatStringsSep " " viewerAddresses}
      abort @outsider
      handle /active {
        root * ${activity}
        file_server
      }
      handle {
        reverse_proxy 127.0.0.1:${toString viewPort}
      }
    '';
  };
}
