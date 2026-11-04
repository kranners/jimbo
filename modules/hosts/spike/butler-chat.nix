{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.users.users.butler) home;
  inherit (config.services.matrix-tuwunel.settings.global) port;

  state = "/var/lib/butler-chat";
  index = "/var/lib/butler-index/db";
  # Butler asks for a rebuild by leaving a file here, which the sync removes.
  refresh = "${home}/chat-refresh";
  credentials = "/run/credentials/butler-chat-sync.service";
  messenger = config.butler.messenger.enable;

  substitutions = {
    "@index@" = "${index}/index.sqlite";
    "@cache@" = "${state}/chat.sqlite";
    # Aaron's people and their handles on each service live in his private memory, never in this public repository.
    "@contacts@" = "${home}/memory/skills/contacts/contacts.json";
    "@refresh@" = "${refresh}/request";
    "@slackToken@" = "${credentials}/slack-token";
    "@matrixToken@" = lib.optionalString messenger "${credentials}/matrix-token";
    "@matrix@" = "http://127.0.0.1:${toString (lib.head port)}/_matrix/client/v3";
  };

  chat = pkgs.writers.writePython3Bin "chat" { flakeIgnore = [ "E501" ]; } (
    builtins.replaceStrings (lib.attrNames substitutions) (lib.attrValues substitutions) (
      builtins.readFile ./butler-chat/chat.py
    )
  );

  # Reads only, of a private cache, so every verb taints the thread through `private` and none sends anything out.
  reads = [
    "interactive"
    "cron"
    "call"
  ];
  verb = name: flags: {
    match = [
      name
      "**"
    ];
    lanes = reads;
    inherit flags;
  };
in
{
  butler.commands.chat = {
    package = chat;
    private = true;
    description = ''
      Read Aaron's conversations across Slack, Messenger, Instagram, Discord, Google Chat, iMessage, SMS and LinkedIn in one shape, both sides where the source holds them, from spike's private cache: read-only, it never sends, reacts or marks anything read.
      chat sources (what each source can see and how fresh) | chat people | chat list [--source S] [--days N] [--limit N] | chat read <person or conversation...> [--source S] [--limit N] | chat search <words...> [--source S] [--limit N] | chat waiting [--days N] (who is waiting on Aaron) | chat refresh (rebuild the cache now)
    '';
    rules = [
      {
        match = [ "sources" ];
        lanes = reads;
      }
      {
        match = [ "people" ];
        lanes = reads;
      }
      (verb "list" [
        "--source"
        "--days"
        "--limit"
      ])
      (verb "read" [
        "--source"
        "--limit"
      ])
      (verb "search" [
        "--source"
        "--limit"
      ])
      (verb "waiting" [ "--days" ])
      {
        match = [ "refresh" ];
        lanes = [
          "interactive"
          "cron"
        ];
      }
    ];
    skill = ./butler-skills/chat;
  };

  systemd.tmpfiles.rules = [
    "d ${state} 0700 butler butler -"
    "d ${refresh} 0700 butler butler -"
  ];

  # The daemon reads the cache only through `chat`, since its own Read of the directory is denied in butler.nix.
  systemd.services.butler.serviceConfig.BindReadOnlyPaths = [ "-${state}" ];

  systemd.services.butler-chat-sync = {
    description = "Rebuild butler's private chat cache from the index and live Slack and Messenger reads";
    wants = [ "network-online.target" ];
    requires = [ "butler-slack-token.service" ];
    after = [
      "network-online.target"
      "butler-slack-token.service"
    ]
    ++ lib.optional messenger "tuwunel.service";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${lib.getExe chat} sync";
      User = "butler";
      Group = "butler";
      UMask = "0077";
      # The same read-only tokens butler's `slack` and `messenger-read` already hold.
      LoadCredential = [
        "slack-token:/var/lib/secrets/butler-slack-token"
      ]
      ++ lib.optional messenger "matrix-token:/var/lib/secrets/butler-matrix-token";
      Nice = 15;
      MemoryMax = "512M";
      TimeoutStartSec = "5min";
      ProtectSystem = "strict";
      PrivateTmp = true;
      NoNewPrivileges = true;
      ReadOnlyPaths = [ "-${index}" ];
      ReadWritePaths = [
        state
        refresh
      ];
    };
  };

  systemd.timers.butler-chat-sync = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnActiveSec = "2min";
      OnUnitInactiveSec = "15min";
    };
  };

  systemd.paths.butler-chat-sync = {
    wantedBy = [ "paths.target" ];
    pathConfig.PathExists = "${refresh}/request";
  };
}
