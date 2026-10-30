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

  jq-filter = pkgs.writeShellApplication {
    name = "jq-filter";
    runtimeInputs = [ pkgs.jq ];
    text = ''
      usage() {
        echo "usage: jq-filter [-r] [-c] [-e] [-S] [-j] <filter>   (reads JSON from stdin only)" >&2
        exit 2
      }

      flags=()
      while [ $# -gt 1 ]; do
        case "$1" in
          -r | -c | -e | -S | -j) flags+=("$1") ;;
          *) usage ;;
        esac
        shift
      done

      [ $# -eq 1 ] || usage
      if [[ $1 =~ (^|[^a-zA-Z_.])(import|include|modulemeta|get_search_list|env)([^a-zA-Z_]|$) || $1 == *"\$ENV"* ]]; then
        echo "jq-filter: filters may not load modules or read the environment" >&2
        exit 2
      fi

      exec jq "''${flags[@]}" -- "$1"
    '';
  };

  # https://github.com/openclaw/openclaw/blob/v2026.10.5/extensions/anthropic/cli-shared.ts
  execApprovals = pkgs.writeText "openclaw-exec-approvals.json" (
    builtins.toJSON {
      version = 1;
      defaults = {
        security = "deny";
        ask = "off";
        askFallback = "deny";
        autoAllowSkills = false;
      };
      agents.main = {
        security = "allowlist";
        ask = "off";
        askFallback = "deny";
        autoAllowSkills = false;
        allowlist = map (command: { pattern = lib.getExe command; }) cfg.commands;
      };
    }
  );

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
      model.primary = "anthropic/claude-sonnet-5-5";
      models."anthropic/claude-sonnet-5-5".agentRuntime.id = "claude-cli";
      thinkingDefault = "low";
    };

    tools = {
      profile = "minimal";
      alsoAllow = [
        "browser"
        "exec"
        "web_search"
        "web_fetch"
        "memory_search"
        "memory_get"
      ];
      deny = [
        "process"
        "code_execution"
        "group:messaging"
        "group:automation"
        "group:nodes"
        "write"
        "edit"
        "apply_patch"
      ];
      exec = {
        host = "gateway";
        mode = "allowlist";
      };
    };

    browser = {
      enabled = true;
      executablePath = lib.getExe chromium;
      headless = false;
      extraArgs = [ "--ozone-platform=wayland" ];
      tabCleanup.enabled = true;
    };
  };

  configFile = pkgs.writeText "openclaw.json" (builtins.toJSON settings);

  workspaceFiles = pkgs.runCommand "openclaw-workspace" { } ''
    mkdir -p $out/skills
    cp ${./SOUL.md} $out/SOUL.md
    cp ${./IDENTITY.md} $out/IDENTITY.md
    cp ${./AGENTS.md} $out/AGENTS.md
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
    rm -rf ${workspace}/TOOLS.md ${
      lib.concatMapStringsSep " " (name: "${workspace}/skills/${name}") (lib.attrNames cfg.skills)
    }
    cp -rL --no-preserve=mode ${workspaceFiles}/. ${workspace}/
    ${lib.getExe pkgs.openclaw} approvals set --file ${execApprovals}
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
      jq-filter
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
