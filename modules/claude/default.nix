{
  sharedHomeModule = {
    home.file.".claude/CLAUDE.md".source = ./CLAUDE.md;
    home.file.".claude/settings.json".text = builtins.toJSON {
      theme = "auto";

      # Model settings
      model = "claude-fable-5[1m]";
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

      # See full tool usages
      verbose = true;
    };
  };
}
