{
  config,
  lib,
  pkgs,
  ...
}:
let
  state = "/var/lib/butler-feeds";
  inbox = "/var/lib/butler-index/inbox";
  mailAccounts = config.butler.mail.accounts;
  credentials = "/run/credentials/butler-feeds.service/";

  # The same himalaya accounts as butler's `mail`, reading their passwords from this unit's own credentials.
  himalayaJson = pkgs.writeText "butler-feeds-himalaya.json" (
    builtins.replaceStrings [ "/run/credentials/butler.service/" ] [ credentials ] (
      builtins.toJSON { accounts = lib.mapAttrs (_: account: account.himalaya) mailAccounts; }
    )
  );
  himalayaConfig = pkgs.runCommand "butler-feeds-himalaya.toml" { } ''
    ${pkgs.remarshal}/bin/json2toml ${himalayaJson} $out
  '';

  # Each account's inbox and archive, by their aliases; Gmail's archive is All Mail, which already holds the inbox.
  mailboxes =
    account:
    let
      archive = account.himalaya.mailbox.alias.archive or null;
    in
    if archive == null then
      [ "inbox" ]
    else if lib.hasInfix "All Mail" archive then
      [ "archive" ]
    else
      [
        "inbox"
        "archive"
      ];

  feedsConfig = pkgs.writeText "butler-feeds.json" (
    builtins.toJSON {
      stateDir = state;
      inherit inbox;
      indexDb = "/var/lib/butler-index/db/index.sqlite";
      himalaya = lib.getExe pkgs.himalaya;
      himalayaConfig = "${himalayaConfig}";
      mailAccounts = lib.mapAttrs (_: mailboxes) mailAccounts;
      timeZone = config.time.timeZone;
    }
  );

  wrapper =
    name: prefix:
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = [ pkgs.python3 ];
      text = ''
        export BUTLER_FEEDS_CONFIG=${feedsConfig}
        export PYTHONTZPATH=${pkgs.tzdata}/share/zoneinfo
        exec python3 -I ${./butler-feeds/feeds.py} ${prefix} "$@"
      '';
    };

  butler-feeds = wrapper "butler-feeds" "run";
  feeds = wrapper "feeds" "";
  feedsLogin = wrapper "butler-feeds-run-login" "login";

  # Aaron runs `sudo butler-feeds-login <feed>` on spike; it drops to butler, so every file it writes is butler's.
  butler-feeds-login = pkgs.writeShellApplication {
    name = "butler-feeds-login";
    runtimeInputs = [ pkgs.util-linux ];
    text = ''
      if [ "$(id -u)" -ne 0 ]; then
        echo "run it as root: sudo butler-feeds-login letterboxd|goodreads|spotify|steam|paypal" >&2
        exit 1
      fi
      umask 077
      exec setpriv --reuid=butler --regid=butler --init-groups ${lib.getExe feedsLogin} "$@"
    '';
  };

  mailCredentials = lib.mapAttrsToList (name: source: "${name}:${source}") (
    lib.mergeAttrsList (lib.catAttrs "credentials" (lib.attrValues mailAccounts))
  );

  reads = [
    "interactive"
    "cron"
    "call"
  ];
in
{
  environment.systemPackages = [ butler-feeds-login ];

  systemd.tmpfiles.rules = [
    "d ${state} 0700 butler butler -"
    "d ${state}/secrets 0700 butler butler -"
    "d ${state}/state 0700 butler butler -"
    "d ${state}/out 0700 butler butler -"
  ];

  # Hourly as butler, outside the daemon's sandbox: it reads the web and Aaron's mail, and writes only its own state
  # and the index inbox's feed files, so the index's own ingest, which reads the inbox read-only, takes them in.
  systemd.services.butler-feeds = {
    description = "Fetch butler's live data feeds into its index inbox";
    wants = [ "network-online.target" ];
    after = [
      "network-online.target"
      "systemd-tmpfiles-setup.service"
    ];
    unitConfig.ConditionPathIsDirectory = inbox;
    serviceConfig = {
      Type = "oneshot";
      User = "butler";
      Group = "butler";
      ExecStart = lib.getExe butler-feeds;
      LoadCredential = mailCredentials;
      Nice = 19;
      IOSchedulingClass = "idle";
      MemoryMax = "512M";
      TimeoutStartSec = "30min";
      UMask = "0077";
      ProtectHome = true;
      ProtectSystem = "strict";
      ProtectProc = "invisible";
      PrivateTmp = true;
      NoNewPrivileges = true;
      TemporaryFileSystem = [ "/var/lib" ];
      BindPaths = [
        state
        inbox
      ]
      # ortie refreshes Outlook's token in place.
      ++ lib.optional config.butler.outlook.enable "${config.users.users.butler.home}/.local/share/ortie";
      BindReadOnlyPaths = [ "-/var/lib/butler-index/db" ];
    };
  };

  systemd.timers.butler-feeds = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "hourly";
      RandomizedDelaySec = "10min";
      Persistent = true;
    };
  };

  # butler sees only the status and the Steam and Spotify snapshots, read-only, through `feeds`, which taints the
  # thread, since its own Read is denied the directory.
  systemd.services.butler.serviceConfig.BindReadOnlyPaths = [ "-${state}/out" ];

  butler.commands.feeds = {
    package = feeds;
    private = true;
    description = ''
      Read butler's live data feeds on spike, read-only: which are connected and which wait on a login of Aaron's (Letterboxd, Goodreads, Spotify, Steam, PayPal, and Hostplus, CMC, Uber and Amazon from mail), Aaron's Steam library and playtime, and his latest Spotify plays; everything they fetch also lands in `life`.
      feeds status | feeds steam [recent|library] [words...] | feeds spotify [count]
    '';
    rules = [
      {
        match = [ "status" ];
        lanes = reads;
      }
      {
        match = [
          "steam"
          "**"
        ];
        lanes = reads;
      }
      {
        match = [
          "spotify"
          "**"
        ];
        lanes = reads;
      }
    ];
  };
}
