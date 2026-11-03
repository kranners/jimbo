{
  config,
  lib,
  pkgs,
  ...
}:
let
  kokoroModel =
    pkgs.runCommand "kokoro-multi-lang-v1_0"
      {
        src = pkgs.fetchurl {
          url = "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/kokoro-multi-lang-v1_0.tar.bz2";
          sha256 = "197pw00088npi2jvd84m8x3nwzdh70zp5sz1c26x9k05ph3kfw30";
        };
      }
      ''
        mkdir $out
        tar xjf $src -C $out --strip-components=1 \
          kokoro-multi-lang-v1_0/{model.onnx,voices.bin,tokens.txt,lexicon-gb-en.txt,espeak-ng-data}
      '';

  wyoming-kokoro = pkgs.writers.writePython3Bin "wyoming-kokoro" {
    libraries = with pkgs.python3Packages; [
      numpy
      sentence-stream
      sherpa-onnx
      wyoming
    ];
    flakeIgnore = [ "E501" ];
  } (builtins.readFile ./voice/kokoro.py);

  kokoroVoice = [
    "--model"
    kokoroModel
    "--voice"
    "bm_george"
    "--speed"
    "1.0"
  ];
in
{
  services.wyoming.faster-whisper.servers.en = {
    enable = true;
    sttLibrary = "sherpa";
    model = "sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8";
    language = "en";
    device = "cpu";
    uri = "tcp://127.0.0.1:10300";
  };

  systemd.services.wyoming-faster-whisper-en.serviceConfig.Nice = 10;

  systemd.services.wyoming-kokoro = {
    description = "Kokoro text to speech for Home Assistant's Assist and butler's calls";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = lib.escapeShellArgs (
        [
          (lib.getExe wyoming-kokoro)
          "--uri"
          "tcp://127.0.0.1:10200"
        ]
        ++ kokoroVoice
      );
      Nice = 10;
      Restart = "always";
      RestartSec = 5;
      DynamicUser = true;
      CapabilityBoundingSet = "";
      DeviceAllow = "";
      DevicePolicy = "closed";
      LockPersonality = true;
      PrivateDevices = true;
      PrivateUsers = true;
      ProtectHome = true;
      ProtectHostname = true;
      ProtectKernelLogs = true;
      ProtectKernelModules = true;
      ProtectKernelTunables = true;
      ProtectControlGroups = true;
      ProtectProc = "invisible";
      RestrictAddressFamilies = [
        "AF_INET"
        "AF_INET6"
        "AF_UNIX"
      ];
      RestrictNamespaces = true;
      RestrictRealtime = true;
      SystemCallArchitectures = "native";
      SystemCallFilter = [
        "@system-service"
        "~@privileged"
      ];
      UMask = "0077";
    };
  };

  systemd.services.home-assistant.preStart = ''
    cd ${config.services.home-assistant.configDir}
    voice=${lib.escapeShellArg (toString kokoroVoice)}
    if [ "$(cat .tts-voice 2>/dev/null)" != "$voice" ]; then
      rm -rf tts
      printf '%s' "$voice" > .tts-voice
    fi
  '';
}
