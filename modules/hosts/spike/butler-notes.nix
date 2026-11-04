{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (import ./butler-notes/packages.nix { inherit pkgs lib; }) note writer;
  home = config.users.users.butler.home;
  notes = "/var/lib/butler-notes";
  # Under ~/.cache, which butler's Read is denied, as `mac fetch`'s spool is.
  spool = "${home}/.cache/notes-write";

  # The vault is Aaron's own notes, so every rule taints the thread like `life`; a write is an `acts` rule, which asks
  # in a thread a voice request or board message began, and nothing reaches the voice lane.
  verb = name: writes: {
    match = [
      name
      "**"
    ];
    lanes = [
      "interactive"
      "cron"
    ]
    ++ lib.optional (!writes) "call";
    acts = writes;
  };
in
{
  butler.commands.note = {
    package = note;
    stdin = true;
    private = true;
    description = ''
      Read and write any note in Aaron's Obsidian vault, Latte, through Obsidian Sync, so a write reaches his phone and Macs: read fresh with its sha256, create, append, replace a whole note you read, list a note's saved versions and restore one; it never deletes. Every write is saved in the vault's history on spike first.
      note read <path> | note create <path> (stdin) | note append <path> (stdin) | note replace <path> <sha256> (stdin: the whole new note) | note history <path> | note restore <path> <commit>
    '';
    rules = [
      (verb "read" false)
      (verb "history" false)
      (verb "create" true)
      (verb "append" true)
      (verb "replace" true)
      (verb "restore" true)
    ];
  };

  systemd.tmpfiles.rules = [
    "d ${spool} 0700 butler butler -"
    "d ${spool}/spool 0700 butler butler -"
    "d ${spool}/results 0700 butler butler -"
  ];

  systemd.paths.butler-notes-write = {
    wantedBy = [ "paths.target" ];
    unitConfig.StartLimitIntervalSec = 0;
    pathConfig = {
      DirectoryNotEmpty = "${spool}/spool";
      TriggerLimitIntervalSec = 0;
    };
  };

  # Outside the daemon's sandbox, as butler with the Obsidian Sync login butler-notes-sync uses: it pulls, writes one
  # note, commits it to /var/lib/butler-notes/history.git, pushes it and logs it to writes.jsonl.
  systemd.services.butler-notes-write = {
    description = "Write butler's note requests into Aaron's Obsidian vault and sync them to Obsidian Sync";
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    unitConfig.StartLimitIntervalSec = 0;
    path = [ config.systemd.package ];
    environment = {
      XDG_CONFIG_HOME = "${notes}/config";
      NOTES_DIR = notes;
      NOTES_WRITE_DIR = spool;
    };
    serviceConfig = {
      Type = "oneshot";
      User = "butler";
      Group = "butler";
      ExecStart = lib.getExe writer;
      UMask = "0077";
      ProtectSystem = "strict";
      ProtectHome = true;
      ProtectProc = "invisible";
      PrivateTmp = true;
      NoNewPrivileges = true;
      ReadWritePaths = [
        notes
        spool
      ];
      TimeoutStartSec = "20min";
    };
  };
}
