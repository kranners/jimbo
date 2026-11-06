{
  config,
  lib,
  pkgs,
  ...
}:
let
  pilot = {
    address = lib.removeSuffix "/32" (
      lib.head
        (lib.findFirst (peer: peer.name == "pilot") null config.networking.wireguard.interfaces.wg0.peers)
        .allowedIPs
    );
    user = "aaronpierce";
  };

  # Messages Aaron types to Butler on the board wait here: the relay drops
  # each into inbox for the daemon, which answers into outbox.
  board = "/var/lib/butler-board";
  boardMessages = config.butler.kanban.boardMessages.enable;
  # The daemon's thread cards, one per Discord thread of the last day, which `kanban threads` sends to the board.
  threadCards = "${config.users.users.butler.home}/.claude/channels/discord/thread-cards.json";

  substitutions = {
    "@host@" = builtins.toJSON pilot;
    "@ssh@" = lib.getExe pkgs.openssh;
    "@selfFix@" = "${config.users.users.butler.home}/self-fix";
    "@board@" = board;
    "@spoolUser@" = "butler";
    "@context@" = lib.getExe config.butler.context.package;
    "@hubMarker@" = config.spike.kanban.hubMarker;
    "@memoryAudit@" = lib.getExe config.butler.memoryAudit;
    "@auditSpool@" = "${config.users.users.butler.home}/.local/state/kanban/audit-spool";
  };

  kanban = pkgs.writers.writePython3Bin "kanban" { flakeIgnore = [ "E501" ]; } (
    builtins.replaceStrings (lib.attrNames substitutions) (lib.attrValues substitutions) (
      builtins.readFile ./butler-kanban/kanban.py
    )
  );

  # Reading the board and keeping it tidy is Butler's own business; acting
  # through a session, which can run anything on pilot, asks Aaron, and one
  # general permission, "kanban board", covers tidying and sessions alike for
  # the rest of the thread.
  reading = [
    "board_snapshot"
    "read_transcript"
    "board_history"
    "find_stickers"
  ];
  tidying = [
    "put_card"
    "close_card"
    "note"
    "watch"
    "look"
    "arrange"
    "put_sticker"
    "delete_annotations"
    "create_region"
    "update_region"
    "delete_region"
  ];
  driving = [
    "ask_session"
    "send_prompt"
    "announce"
    "answer_prompt"
    "approve_safe_prompts"
    "start_session"
    "finish_session"
  ];
in
{
  options.butler.kanban.boardMessages.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Carry messages Aaron types to Butler on the kanban board into Discord turns, and their answers back.";
  };

  config = lib.mkMerge [
    {
      butler.commands.kanban = {
        package = kanban;
        description = ''
          Aaron's kanban board of Claude Code sessions on pilot, as a collaborator beside him: read it, keep his own cards and notes on it, show where he is, watch sessions and drive them.
          kanban <tool>, with the tool's arguments as a JSON object on stdin (nothing for none).
          Reading: ${lib.concatStringsSep ", " reading}. Butler's cards, notes and presence, and tidying: ${lib.concatStringsSep ", " tidying}. Through a session, asking Aaron first: ${lib.concatStringsSep ", " driving}.
          finish_session takes force only in a turn of Aaron's own message naming the session, its name or id or "those sessions", and asking to end it: it ends any session not working right now without asking it, after leaving a hand-off note on its card.
          Aaron's messages from the board's / popup arrive as turns of their own, and the reply goes back to the board.
          answer_prompt with allow_safe true and a session approves every open prompt of that session the board calls safe and lists the rest, left for Aaron with why; approve_safe_prompts, {} or {"sessions": [...]}, does that for every session waiting on him, and spike's sweep runs it every minute.
        '';
        stdin = true;
        rules =
          map (tool: {
            match = [ tool ];
            lanes = [
              "interactive"
              "cron"
              "call"
            ];
            egress = true;
            lookup = true;
          }) reading
          ++ map (tool: {
            match = [ tool ];
            lanes = [ "interactive" ];
            egress = true;
            grant = "kanban board";
          }) tidying
          ++ map (
            tool:
            {
              match = [ tool ];
              lanes = [ "interactive" ];
              taints = true;
              egress = true;
              grant = "kanban board";
            }
            # A forced finish ends a session without asking it, so the daemon runs it only on Aaron's own message.
            // lib.optionalAttrs (tool == "finish_session") { ownerForce = true; }
          ) driving;
        credentials.butler-mac-key = "/var/lib/secrets/butler-mac-key";
        skill = ./butler-skills/kanban;
      };

      # The marker saying the board runs on spike, so the daemon's own `kanban` calls follow a cutover.
      systemd.services.butler.serviceConfig.BindReadOnlyPaths = [
        "-${dirOf config.spike.kanban.hubMarker}"
      ];

      # One card per change on the board, refreshed as butler-self-fix-progress reads each session.
      systemd.services.butler-kanban-sync = {
        description = "Mirror butler's changes onto Aaron's kanban board on pilot";
        wants = [ "network-online.target" ];
        after = [ "network-online.target" ];
        serviceConfig = {
          Type = "oneshot";
          StateDirectory = "butler-kanban";
          Environment = "KANBAN_KNOWN_HOSTS=/var/lib/butler-kanban/known_hosts";
          LoadCredential = "butler-mac-key:/var/lib/secrets/butler-mac-key";
          # A Mac asleep or a board stopped is no failure, so it waits for the next run.
          ExecStart = "${lib.getExe kanban} changes";
          SuccessExitStatus = [ 75 ];
        };
      };

      # One card per Butler thread of the last day, sent whenever the daemon rewrites its thread cards file, and every minute.
      systemd.services.butler.environment.DISCORD_THREAD_CARDS_FILE = threadCards;

      systemd.services.butler-kanban-threads = {
        description = "Mirror butler's Discord threads onto Aaron's kanban board as Butler cards";
        wants = [ "network-online.target" ];
        after = [ "network-online.target" ];
        # The daemon rewrites the file every few seconds while threads are busy, so no start limit holds the path back.
        startLimitIntervalSec = 0;
        environment.KANBAN_THREAD_CARDS = threadCards;
        serviceConfig = {
          Type = "oneshot";
          StateDirectory = "butler-kanban";
          Environment = "KANBAN_KNOWN_HOSTS=/var/lib/butler-kanban/known_hosts";
          LoadCredential = "butler-mac-key:/var/lib/secrets/butler-mac-key";
          # A Mac asleep, a board stopped or a board too old for thread cards is no failure, so it waits for the next run.
          ExecStart = "${lib.getExe kanban} threads";
          SuccessExitStatus = [ 75 ];
        };
      };

      systemd.paths.butler-kanban-threads = {
        wantedBy = [ "paths.target" ];
        pathConfig.PathChanged = threadCards;
      };

      systemd.timers.butler-kanban-threads = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnActiveSec = "1min";
          OnUnitInactiveSec = "1min";
        };
      };

      systemd.timers.butler-kanban-sync = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnActiveSec = "3min";
          OnUnitInactiveSec = "2min";
        };
      };

      # Approves the prompts the board calls safe on every session waiting on Aaron, so no job waits on a click for them,
      # and leaves the guardrails for him; each approval goes to audit/kanban in butler's memory, and the run's time
      # and today's approvals to /var/lib/butler-kanban/safe-sweep.json.
      systemd.services.butler-kanban-safe-prompts = {
        description = "Approve the safe permission prompts of sessions on Aaron's kanban board";
        wants = [ "network-online.target" ];
        after = [ "network-online.target" ];
        serviceConfig = {
          Type = "oneshot";
          StateDirectory = "butler-kanban";
          Environment = "KANBAN_KNOWN_HOSTS=/var/lib/butler-kanban/known_hosts";
          LoadCredential = "butler-mac-key:/var/lib/secrets/butler-mac-key";
          # A Mac asleep or a board stopped is no failure, so it waits for the next run.
          ExecStart = "${lib.getExe kanban} safe-sweep";
          SuccessExitStatus = [ 75 ];
          # The board's call may take 90 s and memory-audit, behind the memory's lock, another 60.
          TimeoutStartSec = "4min";
        };
      };

      systemd.timers.butler-kanban-safe-prompts = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnActiveSec = "1min";
          OnUnitInactiveSec = "1min";
        };
      };
    }

    (lib.mkIf boardMessages {
      systemd.tmpfiles.settings.butler-board = {
        ${board}.d = {
          user = "butler";
          group = "butler";
          mode = "0700";
        };
        "${board}/inbox".d = {
          user = "butler";
          group = "butler";
          mode = "0700";
        };
        "${board}/outbox".d = {
          user = "butler";
          group = "butler";
          mode = "0700";
        };
      };

      systemd.services.butler = {
        environment.DISCORD_BOARD_DIR = board;
        serviceConfig.BindPaths = [ board ];
      };

      # Collects the board's messages every few seconds over one kept-open ssh
      # connection, and carries Butler's answers back.
      systemd.services.butler-board-relay = {
        description = "Carry Aaron's messages from the kanban board on pilot to butler, and its answers back";
        wantedBy = [ "multi-user.target" ];
        wants = [ "network-online.target" ];
        after = [
          "network-online.target"
          "systemd-tmpfiles-setup.service"
        ];
        environment = {
          KANBAN_KNOWN_HOSTS = "/var/lib/butler-kanban/known_hosts";
          KANBAN_CONTROL_DIR = "/run/butler-board-relay";
          KANBAN_RELAY = "1";
          PYTHONUNBUFFERED = "1";
        };
        serviceConfig = {
          StateDirectory = "butler-kanban";
          RuntimeDirectory = "butler-board-relay";
          LoadCredential = "butler-mac-key:/var/lib/secrets/butler-mac-key";
          ExecStart = "${lib.getExe kanban} board-relay";
          Restart = "always";
          RestartSec = 10;
        };
      };
    })
  ];
}
