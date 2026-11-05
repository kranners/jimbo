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
  # A key of its own for speech and realtime calls, preferred over imagine's shared one while it is not empty.
  audioKey = "/var/lib/secrets/butler-openai-audio-key";
  usesAudioKey =
    config.butler.imagine.enable || (config.butler.voice.enable && config.butler.voice.realtime.enable);
in
{
  # LoadCredential fails butler's start when its source is missing, so an empty placeholder
  # stands in until Aaron writes the key, and everything falls back to the shared key meanwhile.
  config.systemd.services = lib.mkIf usesAudioKey {
    butler-openai-audio-key = {
      description = "Create an empty placeholder for butler's dedicated OpenAI audio key until one is written";
      unitConfig.ConditionPathExists = "!${audioKey}";
      serviceConfig = {
        Type = "oneshot";
        UMask = "0077";
      };
      script = ''
        touch ${audioKey}
      '';
    };

    butler = {
      requires = [ "butler-openai-audio-key.service" ];
      after = [ "butler-openai-audio-key.service" ];
    };
  };

  # The same OpenAI key as imagine, so it comes with it.
  config.butler.commands = lib.mkIf config.butler.imagine.enable {
    voice-sample = {
      package = voice-sample;
      description = ''
        Say one line in several voices, OpenAI's realtime voices read in Butler's voice brief and local Kokoro ones, saving a WAV per voice to the outbox named after it, and print their paths to attach and the OpenAI cost.
        voice-sample [voice...] (the line on stdin; no voices means every OpenAI voice and bm_george, bm_lewis, bm_daniel and bm_fable; openai or kokoro picks a set)
        voice-sample --check (checks the OpenAI key may speak and open realtime calls, saying which permission it lacks)
      '';
      stdin = true;
      rules = [
        {
          match = [ "--check" ];
          lanes = [ "interactive" ];
        }
        {
          match = [ "**" ];
          lanes = [ "interactive" ];
        }
      ];
      credentials.openai-api-key = "/var/lib/secrets/butler-openai-api-key";
      credentials.openai-audio-key = audioKey;
      skill = ./butler-skills/voice-sample;
    };
  };
}
