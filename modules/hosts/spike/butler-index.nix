{
  config,
  pkgs,
  lib,
  ...
}:
let
  inherit (lib) mkOption types;
  cfg = config.butler.index;
  python = pkgs.python3Packages;

  state = "/var/lib/butler-index";
  database = "${state}/db/index.sqlite";
  inbox = "${state}/inbox";
  openaiKey = "/var/lib/secrets/butler-openai-api-key";
  upToken = "/var/lib/secrets/butler-index-up-token";
  appleId = "/var/lib/butler/.local/share/pyicloud/apple-id";

  substitutions = {
    "@database@" = database;
    "@inbox@" = inbox;
    "@discordSelfIds@" = lib.concatStringsSep "," cfg.discordSelfIds;
    "@captionModel@" = cfg.captions.model;
    "@inputUsdPerMillion@" = toString cfg.captions.inputUsdPerMillion;
    "@outputUsdPerMillion@" = toString cfg.captions.outputUsdPerMillion;
    "@monthlyCapUsd@" = toString cfg.captions.monthlyCapUsd;
    "@perRun@" = toString cfg.captions.perRun;
  };

  source =
    files:
    builtins.replaceStrings (lib.attrNames substitutions) (lib.attrValues substitutions) (
      lib.concatMapStringsSep "\n\n" (
        file: if builtins.isString file then file else builtins.readFile file
      ) files
    );

  flakeIgnore = [
    "E302"
    "E303"
    "E305"
    "E402"
    "E501"
    "F811"
  ];

  life = pkgs.writers.writePython3Bin "life" { inherit flakeIgnore; } (source [
    ./butler-index/life.py
  ]);

  ingest =
    pkgs.writers.writePython3Bin "butler-index-ingest"
      {
        libraries = [ python.requests ];
        inherit flakeIgnore;
      }
      (source [
        ./butler-index/common.py
        ./butler-index/ingest.py
      ]);

  # photos.py without its main, so the captioner reuses its iCloud session, paging and thumbnails.
  photosLibrary = builtins.replaceStrings [ "if __name__ == \"__main__\":\n    main()" ] [ "" ] (
    builtins.readFile ./butler-photos/photos.py
  );

  caption =
    pkgs.writers.writePython3Bin "butler-photo-caption"
      {
        libraries = [
          python.pyicloud
          python.pillow
          python.pillow-heif
          python.requests
        ];
        inherit flakeIgnore;
      }
      (source [
        photosLibrary
        ./butler-index/common.py
        ./butler-index/caption.py
      ]);

  hardening = {
    User = "butler";
    Group = "butler";
    ProtectHome = true;
    ProtectSystem = "strict";
    ProtectProc = "invisible";
    PrivateTmp = true;
    NoNewPrivileges = true;
    ReadWritePaths = [ "${state}/db" ];
    Nice = 10;
  };

  both = [
    "interactive"
    "cron"
  ];

  verb = name: {
    match = [
      name
      "**"
    ];
    lanes = both;
  };
in
{
  options.butler.index = {
    discordSelfIds = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Aaron's Discord user IDs; a message export naming its authors keeps only these, while the data package, which holds only his own messages, needs none.";
    };
    captions = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "caption iCloud Photos thumbnails with OpenAI daily, on the imagine key, inside monthlyCapUsd";
      };
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
        description = "what captioning may spend a month, part of the $20 a month the OpenAI key is capped at";
      };
      perRun = mkOption {
        type = types.int;
        default = 300;
      };
    };
  };

  config = {
    butler.commands.life = {
      package = life;
      description = ''
        Search Aaron's personal data index, read-only: Up bank payments, Google location history, his own Discord messages and captioned iCloud Photos. Prints capped JSON.
        life sources | life search <words...> [--from YYYY-MM-DD] [--to YYYY-MM-DD] [--source up|location|discord|photos] [--limit N] | life day <YYYY-MM-DD> [YYYY-MM-DD] [--source S] [--limit N] | life spending <YYYY-MM-DD> <YYYY-MM-DD> | life photos <words...> [--from D] [--to D] [--limit N]
      '';
      rules = [
        {
          match = [ "sources" ];
          lanes = both;
        }
      ]
      ++ map verb [
        "search"
        "day"
        "spending"
        "photos"
      ];
      skill = ./butler-skills/life-index;
    };

    systemd.tmpfiles.rules = [
      "d ${state} 0700 butler butler -"
      "d ${state}/db 0700 butler butler -"
      "d ${inbox} 0700 butler butler -"
      "d ${inbox}/discord 0700 butler butler -"
      "d ${inbox}/location 0700 butler butler -"
    ];

    # The daemon sees the index read-only, and its own Read, Glob and Grep are denied it, so only `life`'s capped output reaches a thread.
    systemd.services.butler.serviceConfig.BindReadOnlyPaths = [ "-${state}/db" ];

    systemd.services.butler-index-ingest = {
      description = "Ingest the Discord and location history exports in butler's index inbox";
      serviceConfig = hardening // {
        Type = "oneshot";
        ReadOnlyPaths = [ inbox ];
        ExecStart = "${lib.getExe ingest} files";
      };
    };

    systemd.paths.butler-index-ingest = {
      wantedBy = [ "paths.target" ];
      pathConfig = {
        PathChanged = [
          "${inbox}/discord"
          "${inbox}/location"
        ];
      };
    };

    systemd.timers.butler-index-ingest = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
      };
    };

    systemd.services.butler-index-up = {
      description = "Ingest Up bank transactions into butler's index";
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      unitConfig.ConditionPathExists = upToken;
      serviceConfig = hardening // {
        Type = "oneshot";
        LoadCredential = [ "up-token:${upToken}" ];
        ExecStart = "${lib.getExe ingest} up";
      };
    };

    systemd.timers.butler-index-up = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "10min";
        OnUnitInactiveSec = "6h";
      };
    };

    systemd.services.butler-photo-caption = lib.mkIf cfg.captions.enable {
      description = "Caption new iCloud Photos thumbnails into butler's index, within the monthly OpenAI cap";
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      unitConfig.ConditionPathExists = [
        openaiKey
        appleId
      ];
      environment.PYTHON_KEYRING_BACKEND = "keyring.backends.null.Keyring";
      serviceConfig = hardening // {
        Type = "oneshot";
        LoadCredential = [ "openai-api-key:${openaiKey}" ];
        ReadWritePaths = [
          "${state}/db"
          "/var/lib/butler/.local/share/pyicloud"
        ];
        ExecStart = lib.getExe caption;
        # An expired iCloud session exits 75 and waits for butler-icloud-login, which is no failure to alert on.
        SuccessExitStatus = [ 75 ];
        TimeoutStartSec = "2h";
      };
    };

    systemd.timers.butler-photo-caption = lib.mkIf cfg.captions.enable {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*-*-* 03:17";
        Persistent = true;
      };
    };
  };
}
