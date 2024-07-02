{ pkgs, ... }: {
  home = {
    shellAliases = {
      ns = "nix-shell --command zsh";
    };

    sessionVariables = {
      EDITOR = "vim";
    };
  };

  programs.zsh = {
    enable = true;

    syntaxHighlighting.enable = true;
    historySubstringSearch.enable = true;
    autosuggestion.enable = true;

    plugins = [
      {
        name = "powerlevel10k";
        src = pkgs.zsh-powerlevel10k;
        file = "share/zsh-powerlevel10k/powerlevel10k.zsh-theme";
      }

      {
        name = "powerlevel10k-lean-config";
        src = pkgs.zsh-powerlevel10k;
        file = "share/zsh-powerlevel10k/config/p10k-lean.zsh";
      }

      {
        name = "history-search-multi-word";
        src = pkgs.zsh-history-search-multi-word;
      }
    ];

    # Disable instant prompt to allow instantly starting into Nix shells
    initExtraBeforeCompInit = ''
      typeset -g POWERLEVEL9K_INSTANT_PROMPT=quiet
    '';
  };
}
