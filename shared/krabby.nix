{ pkgs, ... }: {
  home.packages = [ pkgs.krabby ];

  programs.zsh.initExtra = ''
    krabby random --no-title
  '';

  xdg.configFile.krabby = {
    target = "./krabby/config.toml";

    text = ''
      language = 'en'
      shiny_rate = 0.01
    '';
  };
}
