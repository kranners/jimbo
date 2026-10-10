{
  config,
  pkgs,
  lib,
  host,
  ...
}:
let
  inherit (lib) mkOption types;

  cfg = config.openclaw;

  home = config.users.users.${host.username}.home;
  stateDirectory = "${home}/.openclaw";
  workspace = "${stateDirectory}/workspace";
  gatewayPort = 18789;
  gatewayTokenFile = "/var/lib/secrets/openclaw-gateway-token";

  home-assistant-api = pkgs.writeShellApplication {
    name = "home-assistant-api";
    runtimeInputs = [ pkgs.curl ];
    text = ''
      method=$1
      path=$2
      body=''${3:-}

      curl -fsS -X "$method" \
        -H "Authorization: Bearer $(cat /var/lib/secrets/home-assistant-token)" \
        -H "Content-Type: application/json" \
        ''${body:+--data-raw "$body"} \
        "http://10.100.0.1:8123/api/''${path#/}"
    '';
  };

  # https://github.com/openclaw/openclaw/blob/v2026.6.33/extensions/anthropic/cli-backend.ts
  claudeAllowedTools = lib.concatStringsSep "," (
    [ "mcp__openclaw__*" ] ++ map (command: "Bash(${baseNameOf (lib.getExe command)} *)") cfg.commands
  );
  claudeArgs = [
    "-p"
    "--output-format"
    "stream-json"
    "--include-partial-messages"
    "--verbose"
    "--setting-sources"
    "user"
    "--permission-mode"
    "dontAsk"
    "--allowedTools"
    claudeAllowedTools
    "--disallowedTools"
    "ScheduleWakeup,CronCreate,Bash(run_in_background:true),Monitor"
  ];

  chromium = pkgs.ungoogled-chromium;

  settings = {
    gateway = {
      mode = "local";
      port = gatewayPort;
      bind = "lan";
      auth = {
        mode = "token";
        token = {
          source = "file";
          provider = "gatewaytoken";
          id = "value";
        };
      };
      http.endpoints.chatCompletions.enabled = true;
    };

    secrets.providers.gatewaytoken = {
      source = "file";
      path = gatewayTokenFile;
      mode = "singleValue";
    };

    agents.defaults = {
      inherit workspace;
      model.primary = "claude-cli/sonnet";
      thinkingDefault = "low";
      cliBackends.claude-cli = {
        command = lib.getExe pkgs.claude-code;
        args = claudeArgs;
        resumeArgs = claudeArgs ++ [
          "--resume"
          "{sessionId}"
        ];
      };
    };

    tools = {
      profile = "minimal";
      alsoAllow = [
        "browser"
        "web_search"
        "web_fetch"
        "memory_search"
        "memory_get"
      ];
      deny = [
        "group:runtime"
        "group:messaging"
        "group:automation"
        "group:nodes"
        "write"
        "edit"
        "apply_patch"
      ];
      exec.security = "deny";
    };

    browser = {
      enabled = true;
      executablePath = lib.getExe chromium;
      headless = false;
      extraArgs = [ "--ozone-platform=wayland" ];
      tabCleanup = {
        enabled = true;
        idleMinutes = 3;
        sweepMinutes = 1;
      };
    };
  };

  configFile = pkgs.writeText "openclaw.json" (builtins.toJSON settings);

  workspaceFiles = pkgs.runCommand "openclaw-workspace" { } ''
    mkdir -p $out/skills
    cp ${./SOUL.md} $out/SOUL.md
    cp ${./IDENTITY.md} $out/IDENTITY.md
    cp ${./TOOLS.md} $out/TOOLS.md
    ${lib.concatStrings (
      lib.mapAttrsToList (name: source: ''
        cp -rL ${source} $out/skills/${name}
      '') cfg.skills
    )}
  '';

  # OpenClaw reads workspace files only from inside the workspace, so they are
  # copied in rather than linked into the store.
  installWorkspace = pkgs.writeShellScript "openclaw-install-workspace" ''
    mkdir -p ${workspace}/skills
    rm -rf ${
      lib.concatMapStringsSep " " (name: "${workspace}/skills/${name}") (lib.attrNames cfg.skills)
    }
    cp -rL --no-preserve=mode ${workspaceFiles}/. ${workspace}/
  '';

  gateway = pkgs.writeShellScript "openclaw-gateway" ''
    export XDG_RUNTIME_DIR=/run/user/$UID
    export WAYLAND_DISPLAY=wayland-0
    exec ${lib.getExe pkgs.openclaw} gateway run --port ${toString gatewayPort}
  '';
in
{
  options.openclaw = {
    skills = mkOption {
      description = "Skill directories, each holding a SKILL.md, installed into OpenClaw's workspace by name.";
      type = types.attrsOf types.path;
      default = { };
    };

    commands = mkOption {
      description = "Commands Claude Code may run for OpenClaw's skills, each allowed by its package name.";
      type = types.listOf types.package;
      default = [ ];
    };
  };

  config = {
    openclaw.skills.home-assistant = ./skills/home-assistant;
    openclaw.commands = [
      home-assistant-api
      pkgs.jq
    ];

    nixpkgs.config.allowInsecurePredicate = package: lib.getName package == "openclaw";

    environment.systemPackages = [
      pkgs.claude-code
      pkgs.openclaw
    ];

    systemd.services.openclaw-gateway = {
      description = "OpenClaw gateway, the voice assistant's brain";
      wantedBy = [ "multi-user.target" ];
      wants = [
        "network-online.target"
        "cage-tty1.service"
      ];
      after = [
        "network-online.target"
        "cage-tty1.service"
      ];

      path = cfg.commands ++ [
        pkgs.claude-code
        chromium
        "/run/current-system/sw"
      ];

      environment = {
        OPENCLAW_NIX_MODE = "1";
        OPENCLAW_CONFIG_PATH = "${configFile}";
        OPENCLAW_STATE_DIR = stateDirectory;
        DISABLE_AUTOUPDATER = "1";
      };

      serviceConfig = {
        User = host.username;
        WorkingDirectory = home;
        ExecStartPre = installWorkspace;
        ExecStart = gateway;
        Restart = "always";
        RestartSec = 5;
        SuccessExitStatus = [ 143 ];
      };
    };

    networking.firewall.interfaces = lib.genAttrs [ "wlp1s0" "wg0" ] (_: {
      allowedTCPPorts = [ gatewayPort ];
    });
  };
}
