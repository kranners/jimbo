{
  services.wyoming.faster-whisper.servers.en = {
    model = "small-int8";
    language = "en";
    device = "cpu";
    uri = "tcp://127.0.0.1:10300";
  };

  services.wyoming.piper.servers.en = {
    # No Australian voice exists; samples at https://rhasspy.github.io/piper-samples/.
    voice = "en_GB-alan-medium";
    uri = "tcp://127.0.0.1:10200";
  };

  systemd.services.wyoming-faster-whisper-en.serviceConfig.Nice = 10;
  systemd.services.wyoming-piper-en.serviceConfig.Nice = 10;
}
