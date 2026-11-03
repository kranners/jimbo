{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.butler.inbox;
  inherit (config.users.users.butler) home;

  state = "/var/lib/butler-inbox";
  notifySpool = "/var/lib/butler-notify";
  mailAccounts = config.butler.mail.accounts;

  # The same himalaya accounts as butler's `mail`, reading their passwords from this unit's credentials.
  himalayaJson = pkgs.writeText "butler-inbox-himalaya.json" (
    builtins.replaceStrings
      [ "/run/credentials/butler.service/" ]
      [ "/run/credentials/butler-inbox.service/" ]
      (
        builtins.toJSON {
          accounts = lib.mapAttrs (_: account: account.himalaya) mailAccounts;
        }
      )
  );

  himalayaConfig = pkgs.runCommand "butler-inbox-himalaya.toml" { } ''
    ${pkgs.remarshal}/bin/json2toml ${himalayaJson} $out
  '';

  inboxConfig = pkgs.writeText "butler-inbox.json" (
    builtins.toJSON {
      stateDir = state;
      database = "${state}/inbox.db";
      notifyDir = notifySpool;
      himalaya = lib.getExe pkgs.himalaya;
      himalayaConfig = "${himalayaConfig}";
      claude = lib.getExe config.butler.claude;
      claudeConfigDir = "${state}/claude";
      mailAccounts = lib.attrNames mailAccounts;
      ownAddresses = lib.unique (
        lib.mapAttrsToList (_: account: lib.toLower (account.himalaya.email or "")) mailAccounts
      );
      timeZone = config.time.timeZone;
      inherit (cfg)
        pollSeconds
        pingsPerDay
        perSenderPerDay
        senderTriagePerHour
        triagePerDay
        digestAt
        triageModel
        autonomousActions
        ;
      quietStart = cfg.quietHours.start;
      quietEnd = cfg.quietHours.end;
      pageSize = 20;
    }
  );

  script = ./butler-inbox/inbox.py;

  wrapper =
    name: args:
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = [ pkgs.python3 ];
      text = ''
        export BUTLER_INBOX_CONFIG=${inboxConfig}
        export PYTHONTZPATH=${pkgs.tzdata}/share/zoneinfo
        exec python3 -I ${script} ${args} "$@"
      '';
    };

  butler-inbox = wrapper "butler-inbox" "run";
  inbox = wrapper "inbox" "";

  both = [
    "interactive"
    "cron"
  ];

  credentials = lib.mapAttrsToList (name: source: "${name}:${source}") (
    lib.mergeAttrsList (lib.catAttrs "credentials" (lib.attrValues mailAccounts))
  );

  hhmm = lib.types.strMatching "([01][0-9]|2[0-3]):[0-5][0-9]";
in
{
  options.butler.inbox = {
    enable = lib.mkEnableOption "butler's monitor of Aaron's incoming mail, which triages each new message with a model that has no tools and DMs him what matters";

    pollSeconds = lib.mkOption {
      type = lib.types.ints.between 30 600;
      default = 90;
      description = "How often every feed is polled.";
    };

    pingsPerDay = lib.mkOption {
      type = lib.types.ints.positive;
      default = 5;
      description = "Notifications a day before the rest wait for the digest; urgent items are always sent.";
    };

    perSenderPerDay = lib.mkOption {
      type = lib.types.ints.positive;
      default = 2;
      description = "Notifications a day from one sender before the rest wait for the digest.";
    };

    senderTriagePerHour = lib.mkOption {
      type = lib.types.ints.positive;
      default = 10;
      description = "Items an hour from one sender that are triaged; any more go straight to the digest.";
    };

    triagePerDay = lib.mkOption {
      type = lib.types.ints.positive;
      default = 300;
      description = "Items a day the model triages; any more go straight to the digest.";
    };

    quietHours = {
      start = lib.mkOption {
        type = hhmm;
        default = "22:00";
      };
      end = lib.mkOption {
        type = hhmm;
        default = "07:00";
      };
    };

    digestAt = lib.mkOption {
      type = hhmm;
      default = "18:30";
      description = "When the day's digest is sent.";
    };

    triageModel = lib.mkOption {
      type = lib.types.str;
      default = "haiku";
    };

    # Phase 2. Only internal, reversible actions with an executor can be listed;
    # anything outward-facing is only ever suggested to Aaron.
    autonomousActions = lib.mkOption {
      type = lib.types.listOf (lib.types.enum [ "archive-junk" ]);
      default = [ ];
      description = "Actions the monitor takes by itself, each logged with how to undo it; empty means notify only.";
    };
  };

  config = lib.mkIf (cfg.enable && mailAccounts != { }) {
    systemd.tmpfiles.rules = [
      "d ${state} 0750 butler butler -"
      "d ${state}/claude 0700 butler butler -"
      "d ${state}/feedback 0750 butler butler -"
    ];

    systemd.services.butler-inbox = {
      description = "Butler's monitor of Aaron's incoming mail";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [
        "network-online.target"
        "systemd-tmpfiles-setup.service"
      ];
      environment = {
        HOME = state;
        DISABLE_AUTOUPDATER = "1";
      };
      serviceConfig = {
        User = "butler";
        Group = "butler";
        ExecStart = lib.getExe butler-inbox;
        WorkingDirectory = state;
        LoadCredential = credentials;
        Restart = "always";
        RestartSec = 60;
        Nice = 10;
        MemoryHigh = "768M";
        MemoryMax = "1G";
        ProtectHome = true;
        ProtectSystem = "strict";
        ProtectProc = "invisible";
        TemporaryFileSystem = [ "/var/lib" ];
        BindPaths = [
          state
          notifySpool
          # butler-claude's account tokens and cooldowns, so triage spends butler's accounts the same way.
          "${home}/.claude-accounts"
        ]
        # ortie refreshes Outlook's token in place.
        ++ lib.optional config.butler.outlook.enable "${home}/.local/share/ortie";
        PrivateTmp = true;
        NoNewPrivileges = true;
      };
    };

    systemd.services.butler = {
      environment.DISCORD_INBOX_DIR = state;
      serviceConfig.BindPaths = [ state ];
    };

    butler.commands.inbox = {
      package = inbox;
      private = true;
      stdin = true;
      description = ''
        Read the mail monitor's audit log: what came in, how it was labelled and why, what it suggested and did, and record Aaron's feedback on its triage.
        inbox status | inbox recent [count] | inbox search <words>... | inbox show <ref> | inbox why <ref> | inbox log [count] | inbox feedback <ref|-> <useful|not-important|mute-sender|more-urgent|rule> (an optional note on stdin, required for rule)
      '';
      rules =
        map
          (verb: {
            match = [
              verb
              "**"
            ];
            lanes = both;
          })
          [
            "status"
            "recent"
            "search"
            "show"
            "why"
            "log"
          ]
        ++ [
          {
            match = [
              "feedback"
              "*"
              "*"
            ];
            lanes = [ "interactive" ];
          }
        ];
      skill = ./butler-skills/inbox;
    };
  };
}
