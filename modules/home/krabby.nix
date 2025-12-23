{ pkgs, ... }: {
  home.packages = [ pkgs.krabby ];

  programs.zsh.initContent = ''
    if [[ -z "$CURRENT_POKEMON" ]]; then
      export CURRENT_POKEMON="$(krabby random --no-gmax --no-mega --no-regional 1-5 | awk 'NR == 1 {print tolower($0)}')"
    fi

    krabby name "$CURRENT_POKEMON" --no-title
  '';

  xdg.configFile.krabby = {
    target = "./krabby/config.toml";

    text = ''
      language = 'en'
      shiny_rate = 0.01
    '';
  };
}
