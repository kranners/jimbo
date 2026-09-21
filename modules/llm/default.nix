{ lib, config, ... }:
let
  inherit (lib) mkOption types;
in
{
  options.llm = {
    port = mkOption {
      description = "Port the local llama.cpp server listens on.";
      type = types.port;
      default = 8080;
    };

    modelId = mkOption {
      description = "Model name advertised over the OpenAI-compatible API.";
      type = types.str;
      default = "qwen3.5-9b";
    };

    contextSize = mkOption {
      description = "Context window in tokens, matching the OpenClaw llama.cpp catalog.";
      type = types.ints.positive;
      default = 65536;
    };

    baseUrl = mkOption {
      description = "OpenAI-compatible endpoint, for OpenClaw's provider configuration.";
      type = types.str;
      readOnly = true;
      default = "http://127.0.0.1:${toString config.llm.port}/v1";
    };
  };

  config.nixosHomeModule = { pkgs, ... }:
    let
      llama-cpp = pkgs.llama-cpp.override { vulkanSupport = true; };

      model = pkgs.fetchurl {
        url = "https://huggingface.co/unsloth/Qwen3.5-9B-GGUF/resolve/main/Qwen3.5-9B-Q4_K_M.gguf";
        hash = "sha256-A7dHJ6hgpWM44ELEQguz8Esv7Fc0F19MufqFPa9St+g=";
      };
    in
    {
      home.packages = [ llama-cpp ];

      systemd.user.services.llama-server = {
        Unit.Description = "llama.cpp OpenAI-compatible server";

        Service = {
          ExecStart = lib.escapeShellArgs [
            "${llama-cpp}/bin/llama-server"
            "--model"
            model
            "--alias"
            config.llm.modelId
            "--host"
            "127.0.0.1"
            "--port"
            (toString config.llm.port)
            "--ctx-size"
            (toString config.llm.contextSize)
          ];

          Restart = "on-failure";
        };

        Install.WantedBy = [ "default.target" ];
      };
    };
}
