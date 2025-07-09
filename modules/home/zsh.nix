{ lib, ... }: {
  home = {
    shellAliases = {
      ns = "nix-shell --command zsh";
      where-config = "cat $(which nvim) | tail -n 1 | tr ' ' '\\n' | grep init.lua";
    };

    sessionVariables = {
      EDITOR = "nvim";
    };
  };

  programs.starship.enable = true;

  programs.zsh = {
    enable = true;

    zprof.enable = true;
    syntaxHighlighting.enable = true;
    autosuggestion.enable = true;

    initContent = lib.mkOrder 550 ''
      # Explicitly disable Vi mode
      bindkey -e

      eval "$(fnm env --use-on-cd)"
    '';
  };
}
