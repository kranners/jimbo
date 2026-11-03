{
  config,
  lib,
  pkgs,
  ...
}:
let
  token = "/var/lib/secrets/butler-voice-token";
  # The imagine command's key, which the realtime call voice uses too.
  openaiKey = "/var/lib/secrets/butler-openai-api-key";
  # The dedicated audio key, preferred while it is not empty; butler-voice-sample.nix keeps its placeholder.
  audioKey = "/var/lib/secrets/butler-openai-audio-key";
  realtime = config.butler.voice.realtime;
  credential = name: "/run/credentials/butler.service/${name}";

  # The realtime voice's prompt, followed by the first line of every command the full
  # Butler has, so it knows what to hand off without a list kept by hand, leaving out
  # `self-fix`, the old name of `change`.
  realtimePrompt = pkgs.writeText "butler-call-realtime.md" (
    builtins.readFile ./butler-call-realtime.md
    + "\n# The full Butler's commands, which only it runs, through hand_off\n"
    + lib.concatMapStrings (
      name:
      let
        first = lib.head (lib.splitString "\n" (lib.trim config.butler.commands.${name}.description));
      in
      "- ${name}: ${lib.substring 0 240 first}\n"
    ) (lib.filter (name: name != "self-fix") (lib.attrNames config.butler.commands))
  );

  voiceList = "Inbox";

  withVoice = [
    "interactive"
    "cron"
    "voice"
  ];
in
{
  options.butler.voice.enable = lib.mkEnableOption "butler's voice endpoint for Home Assistant's Assist, once butler's daemon on main serves it and accepts the voice lane, and its Discord voice calls";

  options.butler.voice.realtime = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Answer butler's Discord calls with OpenAI's realtime voice in front of the Haiku fast lane, falling back to it when OpenAI refuses or the monthly cap is spent; false goes back to the fast lane alone.";
    };
    model = lib.mkOption {
      type = lib.types.str;
      default = "gpt-realtime-2.1";
      description = "The OpenAI realtime model that answers calls.";
    };
    monthlyUsd = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 10;
      description = "The most the realtime voice may spend in a month, in US dollars, after which calls fall back to the fast lane until the next month.";
    };
  };

  config = lib.mkIf config.butler.voice.enable {
    systemd.services.butler-voice-token = {
      description = "Generate the bearer token Home Assistant sends butler's voice endpoint";
      unitConfig.ConditionPathExists = "!${token}";
      serviceConfig = {
        Type = "oneshot";
        UMask = "0077";
      };
      script = ''
        ${lib.getExe pkgs.openssl} rand -hex 32 >${token}.new
        mv ${token}.new ${token}
      '';
    };

    systemd.services.butler = {
      requires = [ "butler-voice-token.service" ];
      after = [ "butler-voice-token.service" ];
      environment = {
        DISCORD_VOICE_LISTEN = "127.0.0.1:18789";
        DISCORD_VOICE_TOKEN_FILE = credential "voice-token";
        DISCORD_VOICE_MODEL = "haiku";
        DISCORD_VOICE_PROMPT_FILE = "${./butler-voice.md}";
        DISCORD_VOICE_ANNOUNCE_ENTITY = "assist_satellite.framer";
        DISCORD_VOICE_LOG_DIR = "${config.users.users.butler.home}/voice-log";
        DISCORD_HA_URL = "http://127.0.0.1:8123";
        DISCORD_CALL_STT = "tcp://127.0.0.1:10300";
        DISCORD_CALL_TTS = "tcp://127.0.0.1:10200";
        # Kokoro's Lewis, the voice framer's panel speaks in too (voice.nix).
        DISCORD_CALL_VOICE = "bm_lewis";
        DISCORD_CALL_PROMPT_FILE = "${./butler-call.md}";
        DISCORD_CALL_FAST_MODEL = "haiku";
        DISCORD_CALL_FAST_PROMPT_FILE = "${./butler-call-fast.md}";
        # A call's full turns run on a quicker model at low effort, speak as they stream,
        # and an utterance ends after 600 ms of silence rather than the daemon's 800.
        DISCORD_CALL_MODEL = "sonnet";
        DISCORD_CALL_EFFORT = "low";
        DISCORD_CALL_STREAM = "1";
        DISCORD_CALL_SILENCE_MS = "600";
        # Audio Aaron asks to hear on a call: his DM attachments and the outbox.
        DISCORD_FFMPEG = lib.getExe pkgs.ffmpeg-headless;
        DISCORD_PLAY_PATHS = lib.concatStringsSep ":" [
          "${config.users.users.butler.home}/outbox"
          "${config.users.users.butler.home}/.claude/channels/discord/inbox"
        ];
      }
      // lib.optionalAttrs config.butler.credentialedTools {
        DISCORD_HA_TOKEN_FILE = credential "home-assistant-token";
      }
      // lib.optionalAttrs realtime.enable {
        DISCORD_CALL_REALTIME_MODEL = realtime.model;
        # The first file holding a key wins, so the dedicated audio key falls back to the shared one.
        DISCORD_CALL_REALTIME_KEY_FILE = "${credential "openai-audio-key"}:${credential "openai-api-key"}";
        DISCORD_CALL_REALTIME_MONTHLY_USD = toString realtime.monthlyUsd;
        # A Kokoro voice: the realtime model answers in text, spoken by wyoming-kokoro, so calls sound like the panel.
        # An OpenAI voice such as cedar has it speak for itself instead.
        DISCORD_CALL_REALTIME_VOICE = "bm_lewis";
        DISCORD_CALL_REALTIME_PROMPT_FILE = "${realtimePrompt}";
        # Butler's own notes on who he is, read at each call's start so his memory's edits reach it.
        # Then how he sounds, the same brief voice-sample reads its samples with.
        DISCORD_CALL_REALTIME_BRIEF_FILES = "${config.users.users.butler.home}/memory/core/character.md:${./butler-voice-style.md}";
      };
      serviceConfig.LoadCredential = [
        "voice-token:${token}"
      ]
      # imagine and voice-sample already load the same keys under the same names.
      ++ lib.optionals (realtime.enable && !config.butler.imagine.enable) [
        "openai-api-key:${openaiKey}"
        "openai-audio-key:${audioKey}"
      ];
    };

    butler.commands = lib.mkMerge [
      {
        reminders.rules = lib.mkBefore [
          {
            match = [
              "add"
              voiceList
              "**"
            ];
            lanes = [
              "interactive"
              "voice"
            ];
            acts = true;
          }
        ];
      }
      (lib.mkIf config.butler.credentialedTools {
        mail.rules = lib.mkBefore [
          {
            match = [ "unread-counts" ];
            lanes = withVoice;
          }
        ];
        calendar.rules = lib.mkBefore [
          {
            match = [
              "agenda"
              "**"
            ];
            lanes = withVoice ++ [ "call" ];
          }
        ];
      })
    ];
  };
}
