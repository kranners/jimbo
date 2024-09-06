{ pkgs, ... }: {
  home.packages = [ pkgs.krabby ];

  programs.zsh.initExtra = ''
    if [[ "$PWD" == *firenvim* ]]; then
      echo -e '\033[0;31m🔥 FIRE MODE 🔥\033[0m'
    else
      krabby random --no-title
    fi
  '';

  xdg.configFile.krabby = {
    target = "./krabby/config.toml";

    text = ''
      language = 'en'
      shiny_rate = 0.01
    '';
  };
}
