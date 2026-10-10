{
  pkgs,
  lib,
  host,
  ...
}:
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
      "hey_jarvis"
      "--detection-command"
      "/run/current-system/sw/bin/panel-wake"
      "--zeroconf"
    ];
  };

  systemd.services.wyoming-satellite = {
    wants = [ "cage-tty1.service" ];
    after = [ "cage-tty1.service" ];
  };

  networking.firewall.interfaces = lib.genAttrs [ "wlp1s0" "wg0" ] (_: {
    allowedTCPPorts = [ 10700 ];
  });
}
