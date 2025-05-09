{ pkgs, lib, ... }: {
  programs.pyenv = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.rbenv = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.zsh.initContent = lib.mkOrder 550 ''
    # firenvim has no access to brew installed stuff
    eval "$(pyenv virtualenv-init - 2>/dev/null 1>&2)"
    eval "$(fnm env --use-on-cd)"
  '';

  home.packages = [ pkgs.uv ];
}
