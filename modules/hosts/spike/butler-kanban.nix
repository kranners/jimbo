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

  substitutions = {
    "@host@" = builtins.toJSON pilot;
    "@ssh@" = lib.getExe pkgs.openssh;
    "@selfFix@" = "${config.users.users.butler.home}/self-fix";
    "@board@" = board;
    "@spoolUser@" = "butler";
  };

  kanban = pkgs.writers.writePython3Bin "kanban" { flakeIgnore = [ "E501" ]; } (
    builtins.replaceStrings (lib.attrNames substitutions) (lib.attrValues substitutions) (
      builtins.readFile ./butler-kanban/kanban.py
    )
  );

  # Reading the board and keeping it tidy is Butler's own business; acting
  # through a session, which can run anything on pilot, always asks Aaron.
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
          Reading: ${lib.concatStringsSep ", " reading}. Butler's cards, notes and presence, and tidying: ${lib.concatStringsSep ", " tidying}. Through a session, each asking Aaron first unless he asked from the board: ${lib.concatStringsSep ", " driving}.
          Aaron's messages from the board's / popup arrive as turns of their own, and the reply goes back to the board.
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
            board = true;
          }) reading
          ++ map (tool: {
            match = [ tool ];
            lanes = [ "interactive" ];
            egress = true;
            board = true;
          }) tidying
          ++ map (tool: {
            match = [ tool ];
            lanes = [ "interactive" ];
            taints = true;
            egress = true;
            board = true;
          }) driving;
        credentials.butler-mac-key = "/var/lib/secrets/butler-mac-key";
        skill = ./butler-skills/kanban;
      };

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

      systemd.timers.butler-kanban-sync = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnActiveSec = "3min";
          OnUnitInactiveSec = "2min";
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
