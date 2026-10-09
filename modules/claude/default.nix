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
      home.file.".claude/settings.json".text = builtins.toJSON (
        {
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
        }
        // lib.optionalAttrs (host.hostname == "spike") {
          # Tell auto mode that spike's production is a home server
          autoMode.environment = [
            "$defaults"
            "Organization: personal. This machine is spike, Aaron's single-user NixOS home server (a mini PC) on a home LAN with open internet. Aaron is the user; his messages in this transcript are his asks. 'Production' means services on this one box used by a handful of people; nothing is multi-tenant or regulated."
            "Source control: github.com/kranners and every repo under it. Repository visibility still applies: private repo content must not go into public ones."
            "CI/CD deploy targets: a branch lands on its repo's main, then `git pull --ff-only` in /srv/workaholic, ~/workspace/claude-discord-threads or ~/workspace/claude-slack-threads, or `git pull && just` in ~/workspace/jimbo, deploys it. Spike's whole system, including its systemd units, is declared in ~/workspace/jimbo's NixOS modules, and the nix build `just` runs is the preview."
            "Sensitive remote targets: the production database `bowerbird` on 127.0.0.1:5432 (user `bowerbird`) and the containers bowerbird-postgres-1 and bowerbird-ui-1. Reading members' data there is acceptable to Aaron. /srv/bowerbird is a git checkout, so reading its code and history is ordinary local reading, apart from its .env."
            "Secrets management: hand-written files (/srv/bowerbird/.env, ~/.claude/channels/*/.env, /var/lib/workaholic/.config/workaholic/*). Reading a token into a shell variable to call that token's own service is fine; printing, copying or writing secrets needs Aaron to name the secret."
          ];
          autoMode.allow = [
            "$defaults"
            "This applies to spike's production services despite their being production: read-only psql queries against the `bowerbird` database and read-only `docker exec` into bowerbird-postgres-1 or bowerbird-ui-1, excluding env dumps (`env`, `printenv`) and secret files."
            "This applies to spike's production services despite their being production: `systemctl restart|stop` of exact units among workaholic-listen.service, workaholic@<N>.service, bowerbird-*.service, discord-threads.service and slack-threads.service, or `kill <PID>` of their processes, when the user's task involves that service; never pattern kills (`pkill -f`), never `disable`/`mask`, never `docker compose down -v`, and never the unit hosting this session (discord-threads.service for a Discord thread, slack-threads.service for a Slack thread, claude-remote-control.service for claude.ai/code)."
            "Running `git pull --ff-only` in /srv/workaholic, ~/workspace/claude-discord-threads or ~/workspace/claude-slack-threads, or `git pull --ff-only && just` in ~/workspace/jimbo, once the change has landed on that repo's main."
            "Adding or removing labels, commenting on, and closing issues and pull requests in github.com/kranners repos; not deleting or transferring repos, changing visibility or editing branch protection."
            "Local working-tree discards (`git reset --hard`, `git rebase --skip`, `git checkout --theirs`, `git clean`) (not `git clean -x`/`-X`) targeting the worktree this session runs in or created with `git worktree add`, never another session's; not `git stash drop`/`clear`, branch deletion or force-push."
          ];
        }
      );
    };
}
