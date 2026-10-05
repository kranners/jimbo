{ host, ... }:
{
  sharedHomeModule =
    { pkgs, lib, ... }:
    let
      save-branch-context = pkgs.writeShellApplication {
        name = "save-branch-context";
        runtimeInputs = [
          pkgs.git
          pkgs.gawk
        ];

        text = ''
          BRANCH="$(git symbolic-ref --short HEAD)"
          NOTE="$HOME/Documents/Latte/Branches/$BRANCH.md"

          # Branch context is the last h1 section, running to the end of file
          awk '
            /^# / { context = "" }
            { context = context $0 "\n" }
            END { printf "%s", context }
          ' "$(git rev-parse --show-toplevel)/.claude/CLAUDE.md" >"$NOTE"

          echo "Saved to $NOTE"
        '';
      };

      statusline = pkgs.writeShellApplication {
        name = "claude-statusline";
        runtimeInputs = [
          pkgs.git
          pkgs.python3
        ];

        text = ''
          exec python3 ${./statusline.py}
        '';
      };

      agentStatusHook = status: [
        {
          hooks = [
            {
              type = "command";
              command = "zellij-agent-status ${status}";
            }
          ];
        }
      ];
    in
    {
      home.packages = [
        save-branch-context
      ];

      home.file.".claude/CLAUDE.md".text = builtins.readFile ./CLAUDE.md;
      home.file.".claude/skills/commit/SKILL.md".source = ./skills/commit/SKILL.md;
      home.file.".claude/settings.json".text = builtins.toJSON {
        theme = "auto";

        # Model settings
        model = "claude-opus-5-5";
        effortLevel = "high";

        # Start in auto mode
        permissions.defaultMode = "auto";

        # Deploy workaholic on spike
        permissions.allow = [
          "Bash(git -C /srv/workaholic pull --ff-only)"
        ];

        # Plugins
        enabledPlugins = {
          "typescript-lsp@claude-plugins-official" = true;
        };

        # Workflows and builtin skills
        skipWorkflowUsageWarning = false;
        disableBundledSkills = false;
        disableWorkflows = false;
        enableWorkflows = true;

        # Agent teams
        env = {
          CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS = "1";
        }
        // lib.optionalAttrs (host.hostname == "spike") {
          CLAUDE_CODE_ENABLE_TELEMETRY = "1";
          OTEL_METRICS_EXPORTER = "otlp";
          OTEL_EXPORTER_OTLP_METRICS_PROTOCOL = "http/protobuf";
          OTEL_EXPORTER_OTLP_METRICS_ENDPOINT = "http://localhost:9090/api/v1/otlp/v1/metrics";
          OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE = "cumulative";
        };

        # Recaps
        awaySummaryEnabled = false;

        # Disable feedback surveys
        feedbackSurveyRate = 0;

        # Disable prompt suggestions
        promptSuggestionsEnabled = false;

        # Status line
        statusLine = {
          type = "command";
          command = "${statusline}/bin/claude-statusline";
          refreshInterval = 30;
        };

        # Agent status in zellij tab names
        hooks = {
          UserPromptSubmit = agentStatusHook "running";
          Notification = agentStatusHook "input";
          Stop = agentStatusHook "idle";
          SessionEnd = agentStatusHook "";
        };
      };
    };
}
