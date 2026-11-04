{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.users.users.butler) home;
  packs = "/var/lib/butler-context";
  # Butler asks for a pack to be rebuilt by leaving its area's name here, which root's generator clears.
  refresh = "${home}/context-refresh";

  pilot = {
    address = lib.removeSuffix "/32" (
      lib.head
        (lib.findFirst (peer: peer.name == "pilot") null config.networking.wireguard.interfaces.wg0.peers)
        .allowedIPs
    );
    user = "aaronpierce";
  };

  substitutions = {
    "@packs@" = packs;
    "@refresh@" = refresh;
    "@memory@" = "${home}/memory";
    "@work@" = "${home}/memory/context/work.json";
    "@digest@" = config.butler.builders.digest;
    "@ssh@" = lib.getExe pkgs.openssh;
    "@pilot@" = builtins.toJSON pilot;
    "@group@" = "butler";
    "@timeZone@" = config.time.timeZone;
  };

  context = pkgs.writers.writePython3Bin "context" { flakeIgnore = [ "E501" ]; } (
    builtins.replaceStrings (lib.attrNames substitutions) (lib.attrValues substitutions) (
      builtins.readFile ./butler-context/context.py
    )
  );

  # Until the first run writes it, the rule Butler loads every session says the packs are coming.
  placeholder = pkgs.writeText "butler-context-index.md" ''
    # Context packs

    Spike keeps one context pack per area of Aaron's life; the first ones are still being written.
    `context list` shows them once they exist, and `context show <area>` reads one.
  '';

  allLanes = [
    "interactive"
    "cron"
    "call"
    "voice"
  ];
in
{
  options.butler.context.package = lib.mkOption {
    type = lib.types.package;
    readOnly = true;
    internal = true;
    default = context;
    description = "`context`, whose `prefix` verb prints the pack kanban and the change launcher put in front of what they send.";
  };

  config = {
    butler.commands.context = {
      package = context;
      description = ''
        Read spike's context packs, the same compact picture of each area of Aaron's life on every surface: the board and his sessions on pilot, his work, his home and framer, your own systems, and his personal plans.
        context list (the areas and when they were refreshed) | context show <area> | context refresh <area> (rebuild it now, then show it). Areas: board, work, home, butler, personal.
      '';
      # The first rule that matches decides, so the kitchen's two come first and repeat the other lanes:
      # the panel hears only the list and the home pack, which hold nothing the room may not hear.
      rules = [
        {
          match = [ "list" ];
          lanes = allLanes;
        }
        {
          match = [
            "show"
            "home"
          ];
          lanes = allLanes;
        }
        {
          match = [ "show" ];
          lanes = [
            "interactive"
            "cron"
            "call"
          ];
        }
        {
          match = [ "refresh" ];
          lanes = [
            "interactive"
            "cron"
          ];
        }
      ];
      skill = ./butler-skills/context;
    };

    systemd.tmpfiles.rules = [
      "d ${packs} 0750 root butler -"
      "C ${packs}/index.md - - - - ${placeholder}"
      "z ${packs}/index.md 0640 root butler -"
      "d ${refresh} 0700 butler butler -"
      # Loaded with core into every session, so each knows the packs exist and where to read them.
      "L+ ${home}/.claude/rules/context-packs.md - - - - ${packs}/index.md"
    ];

    systemd.services.butler.serviceConfig.BindReadOnlyPaths = [ "-${packs}" ];

    systemd.services.butler-context = {
      description = "Rebuild butler's context packs from its memory, the builders digest, the kanban board and pilot";
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      environment = {
        KANBAN_KNOWN_HOSTS = "/var/lib/butler-kanban/known_hosts";
        # Passed here rather than built in, since kanban's own package runs `context prefix`.
        BUTLER_CONTEXT_KANBAN = lib.getExe config.butler.commands.kanban.package;
      };
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${lib.getExe context} generate";
        LoadCredential = "butler-mac-key:/var/lib/secrets/butler-mac-key";
        Nice = 10;
        TimeoutStartSec = "4min";
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        ReadWritePaths = [
          packs
          refresh
          "-/var/lib/butler-kanban"
        ];
      };
    };

    systemd.timers.butler-context = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnActiveSec = "1min";
        OnUnitInactiveSec = "5min";
      };
    };

    systemd.paths.butler-context = {
      wantedBy = [ "paths.target" ];
      pathConfig.DirectoryNotEmpty = refresh;
    };
  };
}
