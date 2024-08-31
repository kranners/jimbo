{ pkgs, ... }: {
  home = {
    programs.pyenv = {
      enable = true;
      enableZshIntegration = true;
    };

    programs.rbenv = {
      enable = true;
      enableZshIntegration = true;
    };

    home.packages = [ pkgs.fnm ];

    programs.zsh.initExtraBeforeCompInit = ''
      eval "$(pyenv virtualenv-init -)"
      eval "$(fnm env --use-on-cd)"
    '';
  };
}
