{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkOption types;

  cfg = config.butler.remarkable;

  root = "/var/lib/butler-index/remarkable";
  library = "${root}/library";
  token = "/var/lib/secrets/butler-remarkable-token";
  openaiKey = "/var/lib/secrets/butler-openai-api-key";

  python = pkgs.python3Packages;

  sync =
    pkgs.writers.writePython3Bin "butler-remarkable-sync"
      {
        libraries = [
          python.requests
          python.pillow
          python.pymupdf
          python.rmscene
        ];
        flakeIgnore = [ "E501" ];
      }
      (
        builtins.replaceStrings
          [
            "@root@"
            "@model@"
            "@inputUsdPerMillion@"
            "@outputUsdPerMillion@"
            "@monthlyCapUsd@"
          ]
          [
            root
            cfg.transcription.model
            (toString cfg.transcription.inputUsdPerMillion)
            (toString cfg.transcription.outputUsdPerMillion)
            (toString cfg.transcription.monthlyCapUsd)
          ]
          (builtins.readFile ./butler-remarkable/sync.py)
      );

  remarkable =
    pkgs.writers.writePython3Bin "remarkable"
      {
        libraries = [ python.pymupdf ];
        flakeIgnore = [ "E501" ];
      }
      (
        builtins.replaceStrings [ "@library@" ] [ library ] (
          builtins.readFile ./butler-remarkable/remarkable.py
        )
      );

  login = pkgs.writeShellApplication {
    name = "butler-remarkable-login";
    runtimeInputs = [ pkgs.systemd ];
    text = ''
      if [ "$(id -u)" -ne 0 ]; then
        echo "usage: sudo butler-remarkable-login" >&2
        exit 2
      fi
      BUTLER_REMARKABLE_TOKEN=${token} ${lib.getExe sync} login
      systemctl start --no-block butler-remarkable-sync.service
      echo "The import has started. Follow it with: journalctl -fu butler-remarkable-sync"
    '';
  };

  both = [
    "interactive"
    "cron"
  ];

  verb = match: {
    inherit match;
    lanes = both;
  };
in
{
  options.butler.remarkable = {
    enable = lib.mkEnableOption "butler's remarkable command and the mirror of Aaron's reMarkable cloud it reads, once sudo butler-remarkable-login has stored a device token";
    transcription = {
      model = mkOption {
        type = types.str;
        default = "gpt-5-mini";
      };
      inputUsdPerMillion = mkOption {
        type = types.number;
        default = 0.25;
      };
      outputUsdPerMillion = mkOption {
        type = types.number;
        default = 2.0;
      };
      monthlyCapUsd = mkOption {
        type = types.number;
        default = 5;
        description = "what transcribing handwritten pages may spend a month on the imagine key, after which the rest wait for the next month";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.tmpfiles.rules = [
      "d ${root} 0700 butler butler -"
      "d ${library} 0700 butler butler -"
      "d ${root}/state 0700 butler butler -"
    ];

    # The daemon reads the mirror, read-only, only through the remarkable command, since its own Read of /var/lib/butler-index is denied; it never sees the token.
    systemd.services.butler.serviceConfig.BindReadOnlyPaths = [ "-${library}" ];

    environment.systemPackages = [ login ];

    systemd.services.butler-remarkable-sync = {
      description = "Mirror Aaron's reMarkable cloud read-only into butler's index, rendering and transcribing handwritten pages";
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      # A switch leaves a long first import running; the next timer run picks up the new unit.
      restartIfChanged = false;
      # Skips until the login has stored a token, so a missing credential never fails a unit.
      unitConfig.ConditionFileNotEmpty = [
        token
        openaiKey
      ];
      serviceConfig = {
        Type = "oneshot";
        User = "butler";
        Group = "butler";
        UMask = "0077";
        LoadCredential = [
          "remarkable-token:${token}"
          "openai-api-key:${openaiKey}"
        ];
        ExecStart = lib.getExe sync;
        Nice = 19;
        IOSchedulingClass = "idle";
        MemoryMax = "1536M";
        ProtectSystem = "strict";
        ProtectHome = true;
        TemporaryFileSystem = [ "/var/lib" ];
        BindPaths = [ root ];
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectProc = "invisible";
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectKernelLogs = true;
        ProtectControlGroups = true;
        ProtectClock = true;
        ProtectHostname = true;
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;
        NoNewPrivileges = true;
        CapabilityBoundingSet = "";
        SystemCallArchitectures = "native";
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
          "AF_UNIX"
        ];
      };
    };

    systemd.timers.butler-remarkable-sync = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "hourly";
        RandomizedDelaySec = "10min";
        Persistent = true;
      };
    };

    butler.commands.remarkable = {
      private = true;
      package = remarkable;
      description = ''
        Read Aaron's reMarkable library, read-only, from spike's mirror of his reMarkable cloud, synced hourly: it cannot change anything on the tablet or cloud.
        remarkable status | remarkable ls [folder path] | remarkable search <words>... | remarkable cat <document id or path> [first page] [last page] | remarkable page <document id or path> <page number> (saves a PNG to attach and prints its path)
        cat prints each page's typed text, handwriting transcribed by OpenAI, highlights and PDF or EPUB text.
      '';
      rules = map verb [
        [ "status" ]
        [ "ls" ]
        [
          "ls"
          "**"
        ]
        [
          "search"
          "**"
        ]
        [
          "cat"
          "**"
        ]
        [
          "page"
          "**"
        ]
      ];
      skill = ./butler-skills/remarkable;
    };
  };
}
