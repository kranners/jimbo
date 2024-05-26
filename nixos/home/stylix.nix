{ pkgs, config, ... }: {
  stylix = {
    image = config.lib.stylix.pixel "base0A";
    base16Scheme = "${pkgs.base16-schemes}/share/themes/google-light.yaml";

    fonts =
      let
        iosevka = {
          package = pkgs.nerdfonts;
          name = "FiraCode Nerd Font Mono";
        };
      in
      {
        serif = iosevka;
        sansSerif = iosevka;
        monospace = iosevka;
      };
  };
}
