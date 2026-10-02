{ pkgs, ... }:
let
  stateDir = "/home/aaron/.openclaw";
  owners = [ "discord:193903125994799114" ];
  claudeModel = "claude-opus-5-5";

  settingsFile = (pkgs.formats.json { }).generate "openclaw.json" {
    commands.ownerAllowFrom = owners;

    gateway = {
      mode = "local";
      bind = "loopback";
    };

    channels.discord = {
      enabled = true;

      dmPolicy = "allowlist";
      allowFrom = owners;

      token = {
        source = "env";
        provider = "default";
        id = "DISCORD_BOT_TOKEN";
      };
    };

    agents.defaults = {
      model.primary = "anthropic/${claudeModel}";

      models."anthropic/${claudeModel}" = {
        alias = "Claude";
        agentRuntime.id = "claude-cli";
      };

      # CLI backends are text-first and never call tools, so the agent answers
      # questions but cannot drive the browser or the shell. An Anthropic API
      # key would be needed for that.
      #
      # The gateway runs with a minimal PATH, so point the bundled backend at
      # the binary. Claude Code must already be logged in for the same user,
      # and the CLI auth method selected once by hand:
      #   claude auth login
      #   openclaw models auth login --provider anthropic --method cli
      cliBackends.claude-cli.command = "${pkgs.claude-code}/bin/claude";
    };
  };

  openclawEnvironment = {
    OPENCLAW_NIX_MODE = "1";
    OPENCLAW_STATE_DIR = stateDir;
    OPENCLAW_CONFIG_PATH = "${settingsFile}";
  };

  openclaw-new = pkgs.writeShellApplication {
    name = "openclaw-new";

    text = ''
      openclaw tui --session "$(date +%s)"
    '';
  };
in
{
  # nixpkgs marks OpenClaw insecure because it parses untrusted content with
  # an LLM that has full access to the system.
  nixpkgs.config.permittedInsecurePackages = [ "openclaw-2026.6.33" ];

  environment.systemPackages = [
    pkgs.openclaw
    openclaw-new
  ];

  # Point the CLI at the same generated config as the service, and keep it in
  # Nix mode so it refuses to edit that config instead of shadowing it.
  environment.variables = openclawEnvironment;

  systemd.services.openclaw = {
    description = "OpenClaw gateway";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];

    path = [
      "/run/wrappers"
      "/run/current-system/sw"
    ];

    environment = openclawEnvironment;

    serviceConfig = {
      User = "aaron";

      # DISCORD_BOT_TOKEN and OPENCLAW_GATEWAY_TOKEN live here. The file is
      # written by hand, because anything Nix writes lands world-readable in
      # the Nix store.
      EnvironmentFile = "-${stateDir}/.env";

      ExecStart = "${pkgs.openclaw}/bin/openclaw gateway run";
      Restart = "on-failure";
      RestartSec = 10;
    };
  };
}
