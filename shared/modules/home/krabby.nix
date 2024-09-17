{ pkgs, ... }: {
  home.packages = [ pkgs.krabby ];

  programs.zsh.initExtra = ''
    if [[ -z "$CURRENT_POKEMON" ]]; then
      export CURRENT_POKEMON="$(krabby random --no-gmax --no-mega --no-regional | awk 'NR == 1 {print tolower($0)}')"
      alacritty msg config --window-id "$ALACRITTY_WINDOW_ID" "window.title=\"$CURRENT_POKEMON\""
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
