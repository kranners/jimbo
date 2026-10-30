{
  config,
  lib,
  pkgs,
  ...
}:
let
  token = "/var/lib/secrets/butler-voice-token";
  credential = name: "/run/credentials/butler.service/${name}";

  voiceList = "Inbox";

  withVoice = [
    "interactive"
    "cron"
    "voice"
  ];
in
{
  options.butler.voice.enable = lib.mkEnableOption "butler's voice endpoint for Home Assistant's Assist, once butler's daemon on main serves it and accepts the voice lane";

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
        DISCORD_HA_URL = "http://127.0.0.1:8123";
      }
      // lib.optionalAttrs config.butler.credentialedTools {
        DISCORD_HA_TOKEN_FILE = credential "home-assistant-token";
      };
      serviceConfig.LoadCredential = [ "voice-token:${token}" ];
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
        calendar.rules = lib.mkBefore [
          {
            match = [
              "agenda"
              "**"
            ];
            lanes = withVoice;
            taints = true;
          }
        ];
      })
    ];
  };
}
