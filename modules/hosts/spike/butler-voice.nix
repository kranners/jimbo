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
  realtime = config.butler.voice.realtime;
  credential = name: "/run/credentials/butler.service/${name}";

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
      default = "gpt-realtime-2.1-mini";
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
        DISCORD_CALL_VOICE = "bm_george";
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
        DISCORD_CALL_REALTIME_KEY_FILE = credential "openai-api-key";
        DISCORD_CALL_REALTIME_MONTHLY_USD = toString realtime.monthlyUsd;
        DISCORD_CALL_REALTIME_VOICE = "cedar";
        DISCORD_CALL_REALTIME_PROMPT_FILE = "${./butler-call-realtime.md}";
      };
      serviceConfig.LoadCredential = [
        "voice-token:${token}"
      ]
      # imagine already loads the same key under the same name.
      ++ lib.optional (realtime.enable && !config.butler.imagine.enable) "openai-api-key:${openaiKey}";
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
