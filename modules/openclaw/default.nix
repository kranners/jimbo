{
  lib,
  config,
  host,
  ...
}:
let
  inherit (lib) mkOption types;

  inherit (config) llm;
in
{
  options.openclaw = {
    stateDir = mkOption {
      description = "OpenClaw state directory, as an absolute path.";
      type = types.str;
      default = "/home/${host.username}/.openclaw";
    };

    settings = mkOption {
      description = "Contents of openclaw.json, rendered into the Nix store and read in Nix mode.";
      type = types.attrs;

      default = {
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
          model.primary = "local/${llm.modelId}";
          models."local/${llm.modelId}".alias = "Local";
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
            "OPENCLAW_CONFIG_PATH=${settingsFile}"
            "PATH=/run/wrappers/bin:/run/current-system/sw/bin"
          ];

          ExecStart = "${pkgs.openclaw}/bin/openclaw gateway run";
          Restart = "on-failure";
          RestartSec = 10;
        };

        Install.WantedBy = [ "default.target" ];
      };
    };
}
