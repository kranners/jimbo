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

      # Prints every Stack note whose `repo` property, one name or a list, names the session's repository, worktrees included
      stack-notes = pkgs.writeShellApplication {
        name = "claude-stack-notes";
        runtimeInputs = [
          pkgs.git
          pkgs.gawk
          pkgs.gnugrep
          pkgs.coreutils
        ];

        text = ''
          STACK="$HOME/Documents/Latte/Stack"

          COMMON_DIR="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || exit 0
          REPO="$(basename "$(dirname "$COMMON_DIR")")"

          frontmatter_repos() {
            awk '
              NR == 1 && $0 != "---" { exit }
              NR > 1 && $0 == "---" { exit }
              in_list && sub(/^[[:space:]]*-[[:space:]]*/, "") { gsub(/["\047]/, ""); print; next }
              { in_list = 0 }
              NR > 1 && sub(/^repo:[[:space:]]*/, "") {
                gsub(/["\047]/, "")
                if ($0 == "") in_list = 1
                else print
              }
            ' "$1"
          }

          FOUND=0
          for NOTE in "$STACK"/*.md; do
            [ -f "$NOTE" ] || continue
            frontmatter_repos "$NOTE" | grep -xF "$REPO" >/dev/null || continue

            if [ "$FOUND" = 0 ]; then
              echo "The user's Stack notes for $REPO, from their Obsidian vault, hold the project's context across sessions. Read them before starting work."
              echo "Every section of a note is yours to edit, the user's own included: answer their questions under them, tick what is done, and correct or remove what has gone wrong or stale."
              echo "Keep them current without being asked: whenever you learn, decide or finish something a later session would need, update the note in place before ending the turn, saying in your reply what you changed."
            fi
            FOUND=1

            printf '\n=== %s ===\n' "$NOTE"
            cat "$NOTE"
          done

          if [ "$FOUND" = 0 ]; then
            echo "No note in $STACK has the property repo: $REPO."
          fi
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

      # Spike's second account, the work one, logs in under ~/.claude-work
      configDirs = [ ".claude" ] ++ lib.optional (host.hostname == "spike") ".claude-work";

      settings = builtins.toJSON (
        {
          theme = "auto";

          # Model settings
          model = "claude-opus-5-5";
          effortLevel = "high";

          # Spike starts in auto mode so its production keeps the classifier, every other host in bypass mode
          permissions.defaultMode = if host.hostname == "spike" then "auto" else "bypassPermissions";
          skipDangerousModePermissionPrompt = host.hostname != "spike";

          # Messages from Aaron's other sessions arrive without waiting for approval, whatever either session's permission mode
          crossSessionInbound = "accept";

          # Plugins, backlogic's on the Linux hosts alone, and on pilot in its backlogic checkouts alone
          extraKnownMarketplaces =
            lib.optionalAttrs (!pkgs.stdenv.hostPlatform.isDarwin || host.hostname == "pilot")
              {
                backlogic = {
                  source = {
                    source = "github";
                    repo = "backlogic/backlogic";
                  };
                  autoUpdate = true;
                };
              };
          enabledPlugins = {
            "typescript-lsp@claude-plugins-official" = true;
          }
          // lib.optionalAttrs (!pkgs.stdenv.hostPlatform.isDarwin) {
            "backlogic@backlogic" = true;
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

          # Every session is reachable from the Claude app, which also receives its push notifications
          remoteControlAtStartup = true;
          agentPushNotifEnabled = true;
          inputNeededNotifEnabled = true;

          # Disable feedback surveys
          feedbackSurveyRate = 0;

          # Disable prompt suggestions
          promptSuggestionsEnabled = false;

          # Every session starts with the Stack notes for its repository
          hooks.SessionStart = [
            {
              hooks = [
                {
                  type = "command";
                  command = "${stack-notes}/bin/claude-stack-notes";
                }
              ];
            }
          ];

          # Status line
          statusLine = {
            type = "command";
            command = "${statusline}/bin/claude-statusline";
            refreshInterval = 30;
          };
        }
        // lib.optionalAttrs (host.hostname == "pilot") {
          # Every pilot session orchestrates its work with workflows
          ultracode = true;
        }
        // lib.optionalAttrs (host.hostname == "spike") {
          # Tell auto mode that spike's production is a home server
          autoMode.environment = [
            "$defaults"
            "Organization: personal. This machine is spike, Aaron's single-user NixOS home server (a mini PC) on a home LAN with open internet. Aaron is the user; his messages in this transcript are his asks. 'Production' means services on this one box used by a handful of people; nothing is multi-tenant or regulated."
            "Source control: github.com/kranners and every repo under it. Repository visibility still applies: private repo content must not go into public ones."
            "CI/CD deploy targets: a branch lands on its repo's main, then `git pull --ff-only` in ~/workspace/claude-discord-threads, or `git pull && just` in ~/workspace/jimbo, deploys it. Spike's whole system, including its systemd units, is declared in ~/workspace/jimbo's NixOS modules, and the nix build `just` runs is the preview."
            "Sensitive remote targets: the production database `bowerbird` on 127.0.0.1:5432 (user `bowerbird`) and the containers bowerbird-postgres-1 and bowerbird-ui-1. Reading members' data there is acceptable to Aaron. /srv/bowerbird is a git checkout, so reading its code and history is ordinary local reading, apart from its .env."
            "Secrets management: hand-written files (/srv/bowerbird/.env, ~/.claude/channels/*/.env). Reading a token into a shell variable to call that token's own service is fine; printing, copying or writing secrets needs Aaron to name the secret."
          ];
          autoMode.allow = [
            "$defaults"
            "This applies to spike's production services despite their being production: read-only psql queries against the `bowerbird` database and read-only `docker exec` into bowerbird-postgres-1 or bowerbird-ui-1, excluding env dumps (`env`, `printenv`) and secret files."
            "This applies to spike's production services despite their being production: `systemctl restart|stop` of exact units among bowerbird-*.service and discord-threads.service, or `kill <PID>` of their processes, when the user's task involves that service; never pattern kills (`pkill -f`), never `disable`/`mask`, never `docker compose down -v`, and never the unit hosting this session (discord-threads.service for a Discord thread, claude-remote-control.service for claude.ai/code)."
            "Running `git pull --ff-only` in ~/workspace/claude-discord-threads, or `git pull --ff-only && just` in ~/workspace/jimbo, once the change has landed on that repo's main."
            "Adding or removing labels, commenting on, and closing issues and pull requests in github.com/kranners repos; not deleting or transferring repos, changing visibility or editing branch protection."
            "Local working-tree discards (`git reset --hard`, `git rebase --skip`, `git checkout --theirs`, `git clean`) (not `git clean -x`/`-X`) targeting the worktree this session runs in or created with `git worktree add`, never another session's; not `git stash drop`/`clear`, branch deletion or force-push."
          ];
        }
        // lib.optionalAttrs (host.hostname != "spike") {
          # Let secrets copied in the browser reach spike without passing through the transcript
          autoMode.allow = [
            "$defaults"
            "Piping the clipboard straight into a command on spike (`pbpaste | ssh 10.100.0.1 '...'`) that writes a secret there, such as `sudo install ... /dev/stdin <path>` followed by restarting the service that reads it, when Aaron asked for that secret to be written there; never printing, echoing, measuring or otherwise reading the clipboard into the transcript."
          ];
        }
      );
    in
    {
      home.packages = [
        save-branch-context
      ];

      home.file = lib.mergeAttrsList (
        map (configDir: {
          "${configDir}/CLAUDE.md".text = builtins.readFile ./CLAUDE.md;
          "${configDir}/skills/commit/SKILL.md".source = ./skills/commit/SKILL.md;
          "${configDir}/settings.json".text = settings;
        }) configDirs
      );
    };

  # Homebrew's uv keeps up with uv's releases
  darwinSystemModule.homebrew.brews = [ "uv" ];

  darwinHomeModule =
    { pkgs, lib, ... }:
    {
      # Claude Code turns a plugin on for one repository only through that repository's settings
      home.activation.enableBacklogicPluginInCheckouts = lib.mkIf (host.hostname == "pilot") (
        lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          for checkout in "$HOME"/workspace/backlogic "$HOME"/workspace/backlogic--* "$HOME"/workspace/backlogic/.claude/worktrees/*; do
            [ -d "$checkout/.claude" ] || continue
            local_settings="$checkout/.claude/settings.local.json"
            [ -s "$local_settings" ] || echo '{}' >"$local_settings"
            if ${pkgs.jq}/bin/jq '.enabledPlugins["backlogic@backlogic"] = true' "$local_settings" >"$local_settings.new"; then
              mv "$local_settings.new" "$local_settings"
            else
              rm -f "$local_settings.new"
              echo "$local_settings is not JSON, so backlogic's plugin stays off there" >&2
            fi
          done
        ''
      );

      # uv owns claude-swap so `cswap upgrade` can update it in place
      home.activation.installClaudeSwap = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        if [ ! -x "$HOME/.local/bin/cswap" ]; then
          run /opt/homebrew/bin/uv tool install claude-swap \
            || echo "claude-swap install failed, retry with: uv tool install claude-swap" >&2
        fi
      '';
    };
}
