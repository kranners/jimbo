{
  config,
  pkgs,
  lib,
  ...
}:
let
  avatar = ../../../assets/butler/butler-avatar.png;
  character = ../../../assets/butler/character.webp;

  imagine =
    pkgs.writers.writePython3Bin "imagine"
      {
        libraries = [ pkgs.python3Packages.requests ];
        flakeIgnore = [ "E501" ];
      }
      (
        builtins.replaceStrings [ "@avatar@" "@character@" ] [ "${avatar}" "${character}" ] (
          builtins.readFile ./butler-imagine/imagine.py
        )
      );

  both = [
    "interactive"
    "cron"
  ];
in
{
  options.butler.imagine.enable = lib.mkEnableOption "the imagine command, once an OpenAI API key is in /var/lib/secrets/butler-openai-api-key";

  config.butler.commands = lib.mkIf config.butler.imagine.enable {
    imagine = {
      package = imagine;
      description = ''
        Generate a picture with OpenAI's image model, saved to the outbox, and print its path to attach.
        imagine <square|portrait|landscape> | imagine butler <square|portrait|landscape> (prompt on stdin; butler draws Butler himself in the scene)
      '';
      stdin = true;
      rules = [
        {
          match = [ "*" ];
          lanes = both;
        }
        {
          match = [
            "butler"
            "*"
          ];
          lanes = both;
        }
      ];
      credentials.openai-api-key = "/var/lib/secrets/butler-openai-api-key";
      skill = ./butler-skills/imagine;
    };
  };
}
