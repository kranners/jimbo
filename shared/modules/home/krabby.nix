{ pkgs, ... }: {
  home.packages = [ pkgs.krabby ];

  programs.zsh.initExtra = ''
    krabby random --no-title
  '';
}
