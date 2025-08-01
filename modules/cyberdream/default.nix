{ lib, inputs, config, ... }:
let
  inherit (lib) mkOption types;

  theme-filename =
    if
      config.cyberdream-theme == "light"
    then "cyberdream-light"
    else "cyberdream";
in
{
  options = {
    cyberdream-theme = mkOption {
      type = types.enum [ "dark" "light" ];
      default = "light";
    };
  };

  config = {
    sharedHomeModule = {
      programs.alacritty.settings.general.import = [
        "${inputs.alacritty-themes}/${theme-filename}.toml"
      ];
    };
  };
}
