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

  panelVoiceWebhook = "http://spike.local:8123/api/webhook/framer-voice";

  postToPanel = "${lib.getExe pkgs.curl} -fsS --max-time 2 -H 'Content-Type: application/json' -d @- ${panelVoiceWebhook}";

  showOnPanel =
    field:
    pkgs.writeShellScript "show-${field}-on-panel" ''
      ${lib.getExe pkgs.jq} -Rs '{${field}: .}' | ${postToPanel} || true
    '';

  wakeAndClearPanel = pkgs.writeShellScript "wake-and-clear-panel" ''
    /run/current-system/sw/bin/panel-wake
    echo '{"heard": "", "reply": ""}' | ${postToPanel} || true
  '';
in
{
  services.wyoming.openwakeword = {
    enable = true;
    uri = "tcp://127.0.0.1:10400";
  };

  services.wyoming.satellite = {
    enable = true;
    user = host.username;
    name = "framer";
    uri = "tcp://0.0.0.0:10700";
    microphone.autoGain = 5;
    microphone.noiseSuppression = 2;
    sounds.awake = "${pkgs.wyoming-satellite.src}/sounds/awake.wav";
    sounds.done = "${pkgs.wyoming-satellite.src}/sounds/done.wav";
    vad.enable = true;
    extraArgs = [
      "--wake-uri"
      "tcp://127.0.0.1:10400"
      "--wake-word-name"
      "hey_mycroft"
      "--detection-command"
      "${wakeAndClearPanel}"
      "--transcript-command"
      "${showOnPanel "heard"}"
      "--synthesize-command"
      "${showOnPanel "reply"}"
    ];
  };

  systemd.services.wyoming-satellite = {
    wants = [ "cage-tty1.service" ];
    after = [ "cage-tty1.service" ];
    serviceConfig.ExecStartPre = "-${setAudioVolumes}";
  };

  networking.firewall.interfaces = lib.genAttrs [ "wlp1s0" "wg0" ] (_: {
    allowedTCPPorts = [ 10700 ];
  });
}
