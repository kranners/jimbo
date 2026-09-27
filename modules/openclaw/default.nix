{
  lib,
  pkgs,
  config,
  host,
  ...
}:
let
  inherit (lib) mkOption types;

  inherit (config) llm;

  claudeModel = "claude-opus-4-8";
in
{
  options.openclaw = {
    stateDir = mkOption {
      description = "OpenClaw state directory, as an absolute path.";
      type = types.str;
      default = "/home/${host.username}/.openclaw";
    };

    owners = mkOption {
      description = "Chat identities allowed to run owner commands, as <channel>:<id>.";
      type = types.listOf types.str;
      default = [ ];
    };

    settings = mkOption {
      description = "Contents of openclaw.json, rendered into the Nix store and read in Nix mode.";
      type = types.attrs;

      default = {
        commands.ownerAllowFrom = config.openclaw.owners;

        gateway = {
          mode = "local";
          bind = "loopback";
          tailscale.mode = "serve";
        };

        # Small local models call tools unreliably. Narrow the tool surface
        # before considering compat.supportsTools = false.
        tools.toolSearch = true;

        channels.discord = {
          enabled = true;

          token = {
            source = "env";
            provider = "default";
            id = "DISCORD_BOT_TOKEN";
          };
        };

        agents.defaults = {
          model = {
            primary = "local/${llm.modelId}";
            fallbacks = [ "anthropic/${claudeModel}" ];
          };

          models = {
            "local/${llm.modelId}".alias = "Local";

            "anthropic/${claudeModel}" = {
              alias = "Claude";
              agentRuntime.id = "claude-cli";
            };
          };

          # The gateway runs with a minimal PATH, so point the bundled backend
          # at the binary. Claude Code must already be logged in for the same
          # user, and the CLI auth method selected once by hand:
          #   claude auth login
          #   openclaw models auth login --provider anthropic --method cli
          cliBackends.claude-cli.command = "${pkgs.claude-code}/bin/claude";
        };

        models = {
          mode = "merge";

          providers.local = {
            inherit (llm) baseUrl;
            apiKey = "local";
            api = "openai-completions";
            timeoutSeconds = 300;

            models = [
              {
                id = llm.modelId;
                name = "Qwen3.5 9B";
                reasoning = false;
                input = [ "text" ];
                cost = {
                  input = 0;
                  output = 0;
                  cacheRead = 0;
                  cacheWrite = 0;
                };
                contextWindow = llm.contextSize;
                maxTokens = 8192;
              }
            ];
          };
        };
      };
    };
  };

  config.openclaw.owners = [ "discord:193903125994799114" ];

  config.nixosSystemModule = {
    # nixpkgs marks OpenClaw insecure because it parses untrusted content with
    # an LLM that has full access to the system.
    nixpkgs.config.permittedInsecurePackages = [ "openclaw-2026.6.33" ];
  };

  config.nixosHomeModule =
    { pkgs, ... }:
    let
      settingsFile = (pkgs.formats.json { }).generate "openclaw.json" config.openclaw.settings;
    in
    {
      home.packages = [ pkgs.openclaw ];

      # Keep the CLI in Nix mode too, so it refuses to edit the generated
      # config instead of silently shadowing it.
      home.sessionVariables.OPENCLAW_NIX_MODE = "1";

      systemd.user.services.openclaw = {
        Unit = {
          Description = "OpenClaw gateway";
          After = [
            "network-online.target"
            "llama-server.service"
          ];
          Wants = [
            "network-online.target"
            "llama-server.service"
          ];
        };

        Service = {
          # DISCORD_BOT_TOKEN and OPENCLAW_GATEWAY_TOKEN live here. The file is
          # written by hand, because anything Nix writes lands world-readable
          # in the Nix store.
          EnvironmentFile = "-${config.openclaw.stateDir}/.env";

          Environment = [
            "OPENCLAW_NIX_MODE=1"
            "OPENCLAW_STATE_DIR=${config.openclaw.stateDir}"
            "PATH=/run/wrappers/bin:/run/current-system/sw/bin"
          ];

          # The CLI reads $OPENCLAW_STATE_DIR/openclaw.json, so the generated
          # config is copied there rather than read from the store. Nix mode
          # then refuses writes to it, and every restart restores it.
          ExecStartPre = "${pkgs.coreutils}/bin/install -m 600 ${settingsFile} ${config.openclaw.stateDir}/openclaw.json";

          ExecStart = "${pkgs.openclaw}/bin/openclaw gateway run";
          Restart = "on-failure";
          RestartSec = 10;
        };

        Install.WantedBy = [ "default.target" ];
      };
    };
}
