{ pkgs, lib, ... }: {
  home = {
    shellAliases = {
      ns = "nix-shell --command zsh";
      where-config = "cat $(which nvim) | tail -n 1 | tr ' ' '\\n' | grep init.lua";
    };

    sessionVariables = {
      EDITOR = "nvim";

      # TODO: Nix shell can fix this
      PUPPETEER_SKIP_CHROMIUM_DOWNLOAD = "1";
      PUPPETEER_EXECUTABLE_PATH = "which chromium";
    };
  };

  programs.zsh = {
    enable = true;

    zprof.enable = true;
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

    initContent = lib.mkOrder 550 ''
      # Disable instant prompt to allow instantly starting into Nix shells
      typeset -g POWERLEVEL9K_INSTANT_PROMPT=quiet

      # Explicitly disable Vi mode
      bindkey -e
    '';
  };
}
