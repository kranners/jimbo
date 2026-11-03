{
  config,
  pkgs,
  lib,
  ...
}:
let
  voice-sample =
    pkgs.writers.writePython3Bin "voice-sample"
      {
        libraries = with pkgs.python3Packages; [
          requests
          wyoming
        ];
        flakeIgnore = [ "E501" ];
      }
      (
        builtins.replaceStrings [ "@style@" ] [ "${./butler-voice-style.md}" ] (
          builtins.readFile ./butler-voice-sample/voice_sample.py
        )
      );
in
{
  # The same OpenAI key as imagine, so it comes with it.
  config.butler.commands = lib.mkIf config.butler.imagine.enable {
    voice-sample = {
      package = voice-sample;
      description = ''
        Say one line in several voices, OpenAI's realtime voices read in Butler's voice brief and local Kokoro ones, saving a WAV per voice to the outbox named after it, and print their paths to attach and the OpenAI cost.
        voice-sample [voice...] (the line on stdin; no voices means every OpenAI voice and bm_george, bm_lewis, bm_daniel and bm_fable; openai or kokoro picks a set)
      '';
      stdin = true;
      rules = [
        {
          match = [ "**" ];
          lanes = [ "interactive" ];
        }
      ];
      credentials.openai-api-key = "/var/lib/secrets/butler-openai-api-key";
      skill = ./butler-skills/voice-sample;
    };
  };
}
