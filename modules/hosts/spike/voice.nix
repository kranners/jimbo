{
  services.wyoming.faster-whisper.servers.en = {
    enable = true;
    sttLibrary = "sherpa";
    model = "sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8";
    language = "en";
    device = "cpu";
    uri = "tcp://127.0.0.1:10300";
  };

  services.wyoming.piper.servers.en = {
    enable = true;
    # No Australian voice exists; samples at https://rhasspy.github.io/piper-samples/.
    voice = "en_GB-cori-high";
    uri = "tcp://127.0.0.1:10200";
  };

  systemd.services.wyoming-faster-whisper-en.serviceConfig.Nice = 10;
  systemd.services.wyoming-piper-en.serviceConfig.Nice = 10;
}
