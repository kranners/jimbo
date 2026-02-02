{
  darwinSystemModule = {
    # Must be enabled in Darwin system as well as home
    programs.zsh.enable = true;
    programs.zsh.enableGlobalCompInit = false;
  };

  sharedHomeModule = { lib, ... }: {
    home = {
      shellAliases = {
        ns = "nix-shell --command zsh";
        where-config = "cat $(which nvim) | tail -n 1 | tr ' ' '\\n' | grep init.lua";
      };

      sessionVariables = {
        EDITOR = "nvim";
      };

      sessionPath = [
        "$HOME/.local/bin"

        # /scripts is intentionally not managed with Nix.
        "$HOME/scripts"
      ];
    };

    programs.starship.enable = true;

    programs.zsh = {
      enable = true;

      syntaxHighlighting.enable = true;
      autosuggestion.enable = true;

      initContent = lib.mkOrder 550 ''
        # Explicitly disable Vi mode
        bindkey -e

        eval "$(fnm env --use-on-cd)"
      '';
    };
  };
}
