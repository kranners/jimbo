{
  pkgs,
  lib,
  host,
  ...
}:
let
  micVolumeBelowClipping = "0.2";
  speakerVolumeFull = "1.0";

  setAudioVolumes = pkgs.writeShellScript "set-audio-volumes" ''
    export XDG_RUNTIME_DIR=/run/user/$UID
    ${pkgs.wireplumber}/bin/wpctl set-volume @DEFAULT_AUDIO_SOURCE@ ${micVolumeBelowClipping}
    ${pkgs.wireplumber}/bin/wpctl set-volume @DEFAULT_AUDIO_SINK@ ${speakerVolumeFull}
  '';

  wakeRecordingsDir = "/var/lib/wyoming-satellite/recordings";

  homeAssistantWebhook = name: "http://spike.local:8123/api/webhook/${name}";

  postToWebhook =
    name:
    "${lib.getExe pkgs.curl} -fsS --max-time 2 -H 'Content-Type: application/json' -d @- ${homeAssistantWebhook name}";

  thinkingTick = pkgs.runCommand "thinking-tick.wav" { } ''
    ${pkgs.sox}/bin/sox -n -r 22050 -c 1 -b 16 $out synth 0.09 sine 660 fade q 0.005 0.09 0.06 vol 0.15
  '';

  thinkingUnit = "framer-thinking";

  stopThinking = pkgs.writeShellScript "stop-thinking" ''
    export XDG_RUNTIME_DIR=/run/user/$UID
    systemctl --user stop ${thinkingUnit} 2>/dev/null || true
  '';

  # Hooks post to spike in the background, because the satellite waits for each
  # before it plays the next sound or reads the next event.
  wakeAndClearPanel = pkgs.writeShellScript "wake-and-clear-panel" ''
    {
      ${stopThinking}
      /run/current-system/sw/bin/panel-wake
      echo '{"heard": "", "reply": ""}' | ${postToWebhook "framer-voice"}
    } </dev/null >/dev/null 2>&1 &
  '';

  showHeardAndThink = pkgs.writeShellScript "show-heard-and-think" ''
    export XDG_RUNTIME_DIR=/run/user/$UID
    heard=$(cat)
    systemctl --user stop ${thinkingUnit} 2>/dev/null
    systemd-run --user --collect --quiet --unit=${thinkingUnit} -p RuntimeMaxSec=60 -- \
      ${pkgs.runtimeShell} -c 'sleep 0.6; while :; do ${pkgs.pipewire}/bin/pw-play ${thinkingTick}; sleep 1.2; done' \
      >/dev/null 2>&1
    {
      printf %s "$heard" | ${lib.getExe pkgs.jq} -Rs '{heard: .}' | ${postToWebhook "framer-voice"}
    } </dev/null >/dev/null 2>&1 &
  '';

  showReply = pkgs.writeShellScript "show-reply" ''
    reply=$(cat)
    {
      printf %s "$reply" | ${lib.getExe pkgs.jq} -Rs '{reply: .}' | ${postToWebhook "framer-voice"}
    } </dev/null >/dev/null 2>&1 &
  '';

  stopThinkingCommand = pkgs.writeShellScript "stop-thinking-command" ''
    cat >/dev/null
    ${stopThinking}
  '';

  # Cuts off whatever the satellite is playing, and asks Home Assistant to
  # drop the conversation it is running.
  dismissConversation = pkgs.writeShellScript "dismiss-conversation" ''
    ${stopThinking}
    ${pkgs.procps}/bin/pkill -u ${host.username} -x aplay
    echo '{"heard": "", "reply": ""}' | ${postToWebhook "framer-voice"}
    echo '{}' | ${postToWebhook "framer-dismiss"}
  '';

  # Muting cancels Home Assistant's pipeline itself, and a dismissal's reload
  # would race the toggle, unloading the mute switch under it.
  toggleAssistant = pkgs.writeShellScript "toggle-assistant" ''
    ${stopThinking}
    ${pkgs.procps}/bin/pkill -u ${host.username} -x aplay
    echo '{"heard": "", "reply": ""}' | ${postToWebhook "framer-voice"}
    echo '{}' | ${postToWebhook "framer-assistant-toggle"}
  '';

  buttons = pkgs.writers.writePython3 "framer-buttons" {
    libraries = [ pkgs.python3Packages.evdev ];
    flakeIgnore = [ "E501" ];
  } ./buttons.py;
in
{
  services.wyoming.openwakeword = {
    enable = true;
    uri = "tcp://127.0.0.1:10400";
    threshold = 0.7;
  };

  services.wyoming.satellite = {
    enable = true;
    package = pkgs.wyoming-satellite.overridePythonAttrs (old: {
      patches = (old.patches or [ ]) ++ [
        ./wyoming-satellite-reset-wake-on-transcript.patch
        ./wyoming-satellite-listen-after-question.patch
        ./wyoming-satellite-stop-recording-on-error.patch
        ./wyoming-satellite-give-up-without-speech.patch
      ];
    });
    user = host.username;
    name = "framer";
    uri = "tcp://0.0.0.0:10700";
    microphone.autoGain = 5;
    microphone.noiseSuppression = 2;
    sounds.awake = "${pkgs.wyoming-satellite.src}/sounds/awake.wav";
    sounds.done = "${pkgs.wyoming-satellite.src}/sounds/done.wav";
    extraArgs = [
      "--wake-uri"
      "tcp://127.0.0.1:10400"
      "--wake-word-name"
      "hey_mycroft"
      "--mic-no-mute-during-awake-wav"
      "--detection-command"
      "${wakeAndClearPanel}"
      "--transcript-command"
      "${showHeardAndThink}"
      "--synthesize-command"
      "${showReply}"
      "--tts-start-command"
      "${stopThinkingCommand}"
      "--error-command"
      "${stopThinkingCommand}"
      "--disconnected-command"
      "${stopThinkingCommand}"
      "--debug-recording-dir"
      wakeRecordingsDir
    ];
  };

  systemd.services.wyoming-satellite = {
    wants = [ "cage-tty1.service" ];
    after = [ "cage-tty1.service" ];
    startLimitIntervalSec = 0;
    serviceConfig.RestartSec = 5;
    serviceConfig.StateDirectory = "wyoming-satellite";
    serviceConfig.ExecStartPre = "-${setAudioVolumes}";
  };

  systemd.tmpfiles.settings.wake-recordings.${wakeRecordingsDir}.e.age = "14d";

  systemd.services.framer-buttons = {
    description = "Volume up twice dismisses framer's conversation, power toggles its assistant";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      User = host.username;
      SupplementaryGroups = [ "input" ];
      ExecStart = "${buttons} ${dismissConversation} ${toggleAssistant}";
      Restart = "always";
      RestartSec = 5;
    };
  };

  networking.firewall.interfaces = lib.genAttrs [ "wlp1s0" "wg0" ] (_: {
    allowedTCPPorts = [ 10700 ];
  });
}
