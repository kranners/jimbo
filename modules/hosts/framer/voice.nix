{
  pkgs,
  lib,
  host,
  ...
}:
let
  micVolumeBelowClipping = "0.2";

  setMicVolume = pkgs.writeShellScript "set-mic-volume" ''
    export XDG_RUNTIME_DIR=/run/user/$UID
    ${pkgs.wireplumber}/bin/wpctl set-volume @DEFAULT_AUDIO_SOURCE@ ${micVolumeBelowClipping}
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
      "hey_rhasspy"
      "--detection-command"
      "/run/current-system/sw/bin/panel-wake"
    ];
  };

  systemd.services.wyoming-satellite = {
    wants = [ "cage-tty1.service" ];
    after = [ "cage-tty1.service" ];
    serviceConfig.ExecStartPre = "-${setMicVolume}";
  };

  networking.firewall.interfaces = lib.genAttrs [ "wlp1s0" "wg0" ] (_: {
    allowedTCPPorts = [ 10700 ];
  });
}
