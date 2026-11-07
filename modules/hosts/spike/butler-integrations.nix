# Butler's live integration check, as Aaron asked on 7 Nov 2026 so his integrations do not suddenly break: one
# cheap, read-only call per integration with the real credentials, every 6 hours, a few minutes after butler starts
# and on Butler's `integrations run`, classing each as pass, warn, fail, not connected or off with a one-line cause
# and the exact fix, and telling Aaron once of what newly fails or expires within 14 days.
# Nothing it runs sends, posts, pays or changes anything: the writers are checked only for their approval gate.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.users.users.butler) home;
  cfg = config.butler.integrations;
  commands = config.butler.commands;
  unit = "butler-integration-check";
  state = "/var/lib/${unit}";
  out = "/var/lib/butler-audit/integrations.json";
  refresh = "${home}/integrations-refresh";
  credentialsDir = "/run/credentials/${unit}.service/";
  mailAccounts = config.butler.mail.accounts;

  # The same himalaya accounts as butler's `mail`, reading their passwords from this unit's own credentials.
  himalayaJson = pkgs.writeText "${unit}-himalaya.json" (
    builtins.replaceStrings [ "/run/credentials/butler.service/" ] [ credentialsDir ] (
      builtins.toJSON { accounts = lib.mapAttrs (_: account: account.himalaya) mailAccounts; }
    )
  );
  himalayaConfig = pkgs.runCommand "${unit}-himalaya.toml" { } ''
    ${pkgs.remarshal}/bin/json2toml ${himalayaJson} $out
  '';

  # Every command's credential but the Mac and memory keys, which no check here uses; each source exists, since
  # butler.service loads the same files and does not start without them.
  credentials = lib.filterAttrs (
    name: _:
    !lib.elem name [
      "butler-mac-key"
      "memory-deploy-key"
    ]
  ) (lib.mergeAttrsList (lib.catAttrs "credentials" (lib.attrValues commands)));

  placeholders = map (name: "${name}.service") (
    lib.filter (name: config.systemd.services ? ${name}) [
      "butler-github-backlogic-token"
      "butler-google-maps-key"
      "butler-matrix-token"
      "butler-openai-audio-key"
      "butler-slack-token"
      "butler-up-token"
    ]
  );

  # Each writer and a sample of each writing call, every rule taking which must wait on Aaron; none is run.
  writes = [
    {
      command = "mail-send";
      kind = "send";
      calls = [
        [
          "fastmail"
          "someone@example.com"
          "Subject"
        ]
      ];
    }
    {
      command = "slack-send";
      kind = "send";
      calls = [
        [
          "post"
          "#general"
        ]
        [
          "reply"
          "#general"
          "1700000000.000100"
        ]
        [
          "react"
          "#general"
          "1700000000.000100"
          "thumbsup"
        ]
        [
          "edit"
          "#general"
          "1700000000.000100"
        ]
        [
          "delete"
          "#general"
          "1700000000.000100"
        ]
      ];
    }
    {
      command = "messenger-send";
      kind = "send";
      calls = [ [ "room" ] ];
      optional = !config.butler.messenger.enable;
    }
    {
      command = "calendar";
      kind = "write";
      calls = [
        [
          "create"
          "calendar.personal"
          "2026-01-01T10:00:00"
          "2026-01-01T11:00:00"
          "Title"
        ]
        [
          "update"
          "calendar.personal"
          "uid"
        ]
        [
          "delete"
          "calendar.personal"
          "uid"
        ]
      ];
    }
    {
      command = "reminders";
      kind = "write";
      calls = [
        [
          "add"
          "Inbox"
          "Milk"
        ]
        [
          "complete"
          "id"
        ]
        [
          "update"
          "id"
        ]
        [
          "delete"
          "id"
        ]
      ];
    }
    {
      command = "hevy";
      kind = "write";
      calls = [
        [
          "routine"
          "apply"
          "A"
          "0123abcd"
        ]
        [ "bootstrap" ]
      ];
      optional = !config.butler.hevy.enable;
    }
    {
      command = "home";
      kind = "write";
      calls = [
        [
          "call"
          "light.kitchen"
          "turn_on"
        ]
        [
          "zone"
          "create"
          "Gym"
          "1"
          "2"
          "100"
        ]
      ];
    }
  ];

  checkConfig = {
    inherit state out;
    notify = "/run/current-system/sw/bin/butler-notify";
    manifest = config.systemd.services.butler.environment.DISCORD_COMMANDS_FILE;
    commands = lib.mapAttrs (name: c: lib.getExe' c.package name) commands;
    inherit (cfg) coverage;
    inherit writes;
    enabled = {
      inbox = config.butler.inbox.enable;
      garmin = config.butler.garmin.enable;
      hevy = config.butler.hevy.enable;
      messenger = config.butler.messenger.enable;
      remarkable = config.butler.remarkable.enable;
      drive = config.butler.drive.enable;
    };
    himalaya = lib.getExe pkgs.himalaya;
    himalayaConfig = "${himalayaConfig}";
    mail = lib.mapAttrs (
      name: account:
      let
        names = lib.attrNames account.credentials;
      in
      {
        credential = if names == [ ] then null else lib.head names;
        tokenFile = if name == "outlook" then "${home}/.local/share/ortie/outlook.json" else null;
        fix =
          if name == "outlook" then
            "sudo -u butler butler-outlook-login"
          else
            "make a new app password for the ${name} account, write it to ${
              lib.head (lib.attrValues account.credentials ++ [ "/var/lib/secrets" ])
            }, then systemctl restart butler";
      }
    ) mailAccounts;
    workGoogle =
      if config.butler.workGoogle.enable && config.butler.credentialedTools then
        lib.getExe' config.butler.workGoogle.package "work-google"
      else
        null;
    workGoogleFix = "sudo -u butler butler-work-google-login <work address>";
    inboxStatus = "/var/lib/butler-inbox/status.json";
    inboxState = "/var/lib/butler-inbox/state";
    homeAssistant = "http://127.0.0.1:8123";
    icloudAppleId = "${home}/.local/share/pyicloud/apple-id";
    garminToken = "${home}/.cache/garmin/token";
    hevySession = "${home}/.cache/hevy/session.json";
    feedsStatus = "/var/lib/butler-feeds/out/status.json";
    # The reader's scopes, which it must keep and the writer's, which it must not hold, as butler-slack.nix lists them.
    slackRead = [
      "channels:history"
      "channels:read"
      "groups:history"
      "groups:read"
      "im:history"
      "im:read"
      "mpim:history"
      "mpim:read"
      "search:read"
      "users:read"
    ];
    slackWrite = [
      "chat:write"
      "reactions:write"
      "im:write"
      "mpim:write"
      "groups:write"
    ];
    slackWriteLookup = [
      "channels:read"
      "groups:read"
      "im:read"
      "mpim:read"
      "users:read"
    ];
    matrix = "http://127.0.0.1:6167";
    chatDb = "/var/lib/butler-chat/chat.sqlite";
    notesConfig = "/var/lib/butler-notes/config/obsidian-headless/sync";
    notesVault = "/var/lib/butler-notes/vault";
    remarkableStatus = "/var/lib/butler-index/remarkable/library/status.json";
    rcloneConfig = "${home}/.config/rclone/rclone.conf";
    mapsUsage = "${home}/.local/state/maps/usage.json";
    mapsLimits = {
      places = 900;
      routes = 5000;
    };
    mindbodyUrl = "https://go.mindbodyonline.com/book/widgets/schedules/view/f25308655e3/schedule";
    monitorProm = "/var/lib/claude-limits/butler-monitor.prom";
    sweepProm = "/var/lib/claude-limits/backlogic-sweep.prom";
    githubFix = lib.mapAttrs (_: i: i.fix) config.spike.github.identities;
    backlogic = "http://127.0.0.1:4200";
    backlogicPeer = "https://ideas.noodlebra.in/";
    kanbanMarker = config.spike.kanban.hubMarker;
    realtimeModel = config.butler.voice.realtime.model;
    claudeLimits = map (account: "/var/lib/claude-limits/claude-limits-${account}.prom") [
      "personal"
      "work"
    ];
    butlerCooldowns = "${home}/.claude-accounts/cooldown";
    butlerAccounts = "${home}/.claude-accounts/tokens";
    dataSources = "${home}/memory/skills/data-sources/data-sources.json";
    indexDb = "/var/lib/butler-index/db/index.sqlite";
    indexInbox = "/var/lib/butler-index/inbox";
    # Folders the ingest reads on arrival by their own units, never waiting.
    inboxSkip = [
      "browser"
      "messages"
    ];
    machines = config.butler.monitor.snapshot;
    caddyAddress = "10.100.0.1";
    sites = import ../../spike-dns/names.nix;
    systemctl = "${config.systemd.package}/bin/systemctl";
  };

  configFile = pkgs.writeText "${unit}.json" (builtins.toJSON checkConfig);

  check = pkgs.writers.writePython3Bin unit {
    flakeIgnore = [
      "E501"
      "E731"
      "W503"
    ];
  } (builtins.readFile ./butler-integrations/check.py);

  # Butler's `integrations`: the last results, read from the status file, and `run`, which asks spike for a fresh
  # check through the request folder and waits for it, since butler cannot start a unit itself.
  integrations = pkgs.writeShellApplication {
    name = "integrations";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.jq
    ];
    text = ''
      status=${out}
      show() {
        [ -r "$status" ] || { echo "integrations: no check has run yet; integrations run asks for one" >&2; exit 75; }
        jq -r --arg want "''${1:-}" --arg id "''${2:-}" '
          def line: "\(.status | ascii_upcase) \(.name) [\(.id)]: \(.cause)" + (if (.status != "pass" and .status != "off" and (.fix // "") != "") then " | fix: \(.fix)" else "" end);
          "Checked \(.generated | strflocaltime("%a %-d %b %H:%M")): \(.summary.pass) pass, \(.summary.warn) warn, \(.summary.fail) fail, \(.summary["not connected"]) not connected, \(.summary.off) off.",
          (if $want == "failing" then (.checks[] | select(.status == "fail" or .status == "warn") | line)
           elif $want == "show" then (.checks[] | select(.id == $id) | line, "expires: \(if .expires then (.expires | strflocaltime("%Y-%m-%d")) else "no expiry known" end)")
           elif $want == "untested" then (.noLiveCheck[] | "\(.command): \(.reason)")
           else (.checks[] | line) end)' "$status"
      }
      case "''${1:-status}" in
        status) [ $# -le 1 ] || exit 2; show ;;
        failing) [ $# -eq 1 ] || exit 2; show failing ;;
        untested) [ $# -eq 1 ] || exit 2; show untested ;;
        show) [ $# -eq 2 ] || exit 2; show show "$2" ;;
        run)
          [ $# -eq 1 ] || exit 2
          before=$(stat -c %Y "$status" 2>/dev/null || echo 0)
          mkdir -p ${refresh}
          date +%s > ${refresh}/request
          for _ in $(seq 50); do
            sleep 1
            now=$(stat -c %Y "$status" 2>/dev/null || echo 0)
            if [ "$now" -gt "$before" ]; then show; exit 0; fi
          done
          echo "integrations: the check is still running; integrations status shows it once it ends" >&2
          exit 75
          ;;
        *) echo "usage: integrations [status|failing|untested|show <id>|run]" >&2; exit 2 ;;
      esac
    '';
  };

  read = match: {
    inherit match;
    lanes = [
      "interactive"
      "cron"
      "call"
    ];
  };

  coverageType = lib.types.either (lib.types.nonEmptyListOf (lib.types.strMatching "[a-z][a-z0-9-]*")) (
    lib.types.strMatching "none: .+"
  );
in
{
  options.butler.integrations.coverage = lib.mkOption {
    type = lib.types.attrsOf coverageType;
    default = { };
    description = "For every one of butler's commands, the live checks of `butler-integration-check` that cover it, or `none: <why it has no live check>`; a command with neither fails the build, so coverage cannot silently rot.";
  };

  config = {
    assertions = [
      {
        assertion = lib.attrNames commands == lib.attrNames (lib.intersectAttrs commands cfg.coverage);
        message = "butler.integrations.coverage (modules/hosts/spike/butler-integrations.nix) has no entry for ${lib.concatStringsSep ", " (lib.attrNames (removeAttrs commands (lib.attrNames cfg.coverage)))}: name the live checks that cover each new command, or give \"none: <why>\"";
      }
    ];

    butler.integrations.coverage = import ./butler-integrations/coverage.nix;

    butler.commands.integrations = {
      package = integrations;
      description = ''
        The live integration check's last results: one read-only call per integration every 6 hours with the real credentials, each pass, warn, fail, not connected or off, with its cause and fix.
        integrations [status] | integrations failing | integrations untested | integrations show <id> | integrations run (asks spike for a fresh check, waiting up to 50 seconds)
      '';
      rules = map read [
        [ ]
        [ "status" ]
        [ "failing" ]
        [ "untested" ]
        [
          "show"
          "*"
        ]
        [ "run" ]
      ];
      skill = ./butler-skills/integrations;
    };

    systemd.tmpfiles.rules = [ "d ${refresh} 0700 butler butler -" ];

    systemd.services.${unit} = {
      description = "Check each of Butler's integrations with one read-only live call, and tell Aaron of new failures";
      # The units that make an empty placeholder for a credential not written yet, since a missing source stops a unit starting.
      wants = [ "network-online.target" ] ++ placeholders;
      after = [ "network-online.target" ] ++ placeholders;
      environment = {
        INTEGRATIONS_CONFIG = "${configFile}";
        HOME = home;
      };
      path = [ pkgs.coreutils ];
      serviceConfig = {
        Type = "oneshot";
        User = "butler";
        Group = "butler";
        SupplementaryGroups = [ "butler-notify" ];
        StateDirectory = unit;
        StateDirectoryMode = "0700";
        LoadCredential = lib.mapAttrsToList (name: source: "${name}:${source}") credentials;
        ExecStartPre = "${pkgs.coreutils}/bin/rm -f ${refresh}/request";
        ExecStart = lib.getExe check;
        TimeoutStartSec = 600;
        Nice = 10;
        MemoryMax = "1G";
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        NoNewPrivileges = true;
        # Butler's home, where pyicloud, rclone, ortie and Hevy refresh their sessions in place, its results folder and the notify spool.
        ReadWritePaths = [
          home
          "-/var/lib/butler-audit"
          "-/var/lib/butler-notify"
        ];
      };
    };

    systemd.timers.${unit} = {
      description = "Check Butler's integrations every 6 hours";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*-*-* 01,07,13,19:23:00";
        Persistent = true;
        RandomizedDelaySec = 300;
      };
    };

    # A few minutes after every start of butler, a deploy's restart above all, so a landing that broke one is caught.
    systemd.timers."${unit}-after-start" = {
      description = "Check Butler's integrations 4 minutes after butler starts";
      timerConfig = {
        OnActiveSec = "4min";
        RemainAfterElapse = false;
        Unit = "${unit}.service";
      };
    };

    systemd.services.butler.serviceConfig.ExecStartPost = [
      "+${pkgs.systemd}/bin/systemctl restart --no-block ${unit}-after-start.timer"
    ];

    systemd.paths.${unit} = {
      description = "Check Butler's integrations when Butler asks";
      wantedBy = [ "paths.target" ];
      pathConfig.DirectoryNotEmpty = refresh;
    };
  };
}
