{ pkgs, ... }:
let
  socket = "/run/butler-note.sock";
  notes = "/var/lib/butler-notes";
  config = "${notes}/config/obsidian-headless";
  mirror = "${notes}/vault";

  # The wrapper butler runs: it hands the request and the note's text to the
  # socket, so the writer, which holds the Obsidian login, runs outside the daemon.
  note = pkgs.writeShellApplication {
    name = "note";
    runtimeInputs = [
      pkgs.socat
      pkgs.jq
      pkgs.coreutils
    ];
    text = ''
      if [ $# -ne 2 ] || { [ "$1" != create ] && [ "$1" != append ]; }; then
        echo "usage: note create|append <path under Butler/>  (the text on stdin)" >&2
        exit 2
      fi
      { jq -cn --arg op "$1" --arg path "$2" '{op: $op, path: $path}'; cat; } |
        exec socat -t 58 - UNIX-CONNECT:${socket}
    '';
  };

  writer = pkgs.writers.writePython3Bin "butler-note-write" {
    flakeIgnore = [
      "E501"
      "W503"
    ];
  } (builtins.readFile ./butler-notes/note.py);
in
{
  systemd.sockets.butler-note = {
    description = "Socket butler's note command writes Obsidian notes through";
    wantedBy = [ "sockets.target" ];
    socketConfig = {
      ListenStream = socket;
      Accept = true;
      SocketUser = "root";
      SocketGroup = "butler";
      SocketMode = "0660";
      MaxConnections = 2;
    };
  };

  # One instance per write, as butler but outside the daemon's sandbox, so it
  # reads the mirror's Obsidian login, which the daemon never sees.
  systemd.services."butler-note@" = {
    description = "Write a note under Butler/ in Aaron's Obsidian vault through Obsidian Sync";
    environment = {
      NOTE_OB = "${pkgs.obsidian-headless}/bin/ob";
      NOTE_CONFIG = config;
      NOTE_MIRROR = mirror;
      HOME = "/tmp";
      LANG = "C.UTF-8";
    };
    serviceConfig = {
      User = "butler";
      Group = "butler";
      StandardInput = "socket";
      StandardOutput = "socket";
      StandardError = "journal";
      ExecStart = "${writer}/bin/butler-note-write";
      RuntimeMaxSec = 70;
      UMask = "0077";
      MemoryMax = "1G";
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      PrivateDevices = true;
      ProtectProc = "invisible";
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      TemporaryFileSystem = [ "/var/lib" ];
      BindReadOnlyPaths = [
        "-${config}"
        "-${mirror}"
      ];
      InaccessiblePaths = [ "-/srv" ];
    };
  };

  butler.commands.note = {
    package = note;
    description = ''
      Write to Aaron's Obsidian vault, Latte, only inside its Butler/ folder: never his other notes, and never delete. The text goes on stdin; the note reaches Obsidian Sync at once, so his devices get it as they sync.
      note create <path> | note append <path>. <path> is under Butler/, such as "Tokyo trip" or "Travel/Tokyo packing list" (".md" and the "Butler/" prefix are optional). create refuses a note that exists; append adds the text to the end of an existing one.
    '';
    stdin = true;
    rules = [
      {
        match = [ "create" ];
        lanes = [
          "interactive"
          "cron"
        ];
        acts = true;
      }
      {
        match = [ "append" ];
        lanes = [
          "interactive"
          "cron"
        ];
        acts = true;
      }
    ];
  };
}
