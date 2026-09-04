{
  sharedHomeModule = { pkgs, ... }:
    let
      save-branch-context = pkgs.writeShellApplication {
        name = "save-branch-context";
        runtimeInputs = [ pkgs.git pkgs.gawk ];

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
    in
  {
    home.packages = [ save-branch-context ];

    home.file.".claude/CLAUDE.md".source = ./CLAUDE.md;
    home.file.".claude/settings.json".text = builtins.toJSON {
      theme = "auto";

      # Model settings
      model = "claude-opus-5";
      effortLevel = "high";

      # Start in auto mode
      permissions.defaultMode = "auto";

      # Plugins
      enabledPlugins = {
        "typescript-lsp@claude-plugins-official" = true;
      };

      # Disable builtin workflows eg code-review
      skipWorkflowUsageWarning = false;
      disableBundledSkills = true;

      # Recaps
      awaySummaryEnabled = false;

      # Disable feedback surveys
      feedbackSurveyRate = 0;

      # Disable prompt suggestions
      promptSuggestionsEnabled = false;

      # Allow editing of current working copy
      worktree.bgIsolation = "none";
    };
  };
}
