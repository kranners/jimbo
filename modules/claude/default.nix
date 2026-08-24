{
  sharedHomeModule = {
    home.file.".claude/CLAUDE.md".source = ./CLAUDE.md;
    home.file.".claude/settings.json".text = builtins.toJSON {
      theme = "auto";

      # Model settings
      model = "claude-opus-4-8";
      effortLevel = "high";

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
