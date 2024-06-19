{ pkgs, ... }:
let
  custom-powerlevel10k = pkgs.zsh-powerlevel10k.overrideAttrs (prev: {
    patches = prev.patches ++ [ ../../packages/zsh-powerlevel10k/vi-mode.patch ];
  });
in
{
  programs.zsh = {
    enable = true;

    syntaxHighlighting.enable = true;
    historySubstringSearch.enable = true;
    autosuggestion.enable = true;

    plugins = [
      {
        name = "powerlevel10k";
        src = custom-powerlevel10k;
        file = "share/zsh-powerlevel10k/powerlevel10k.zsh-theme";
      }

      {
        name = "powerlevel10k-lean-config";
        src = custom-powerlevel10k;
        file = "share/zsh-powerlevel10k/config/p10k-lean.zsh";
      }

      {
        name = "history-search-multi-word";
        src = pkgs.zsh-history-search-multi-word;
      }

      {
        name = "vi-mode";
        src = pkgs.zsh-vi-mode;
        file = "share/zsh-vi-mode/zsh-vi-mode.plugin.zsh";
      }
    ];

    # Disable instant prompt to allow instantly starting into Nix shells
    initExtraBeforeCompInit = ''
      typeset -g POWERLEVEL9K_INSTANT_PROMPT=quiet
    '';

    # Stop the 200ms delay when switching between Vi modes
    initExtraFirst = ''
      function zvm_config() {
        ZVM_LINE_INIT_MODE=$ZVM_MODE_INSERT

        ZVM_KEYTIMEOUT="0"
        ZVM_ESCAPE_KEYTIMEOUT="0"
      }
    '';
  };
}
