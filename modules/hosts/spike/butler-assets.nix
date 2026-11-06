{
  config,
  pkgs,
  lib,
  ...
}:
let
  home = config.users.users.butler.home;
  store = "${home}/assets";
  outbox = "${home}/outbox";

  asset =
    pkgs.writers.writePython3Bin "asset"
      {
        flakeIgnore = [ "E501" ];
      }
      (
        builtins.replaceStrings
          [ "@store@" "@outbox@" "@sources@" "@sensitive@" ]
          [
            store
            outbox
            # What butler made or mac fetched, what Aaron attached, and the store itself, so a source is never a file the daemon's Read is denied.
            (lib.concatStringsSep ":" (
              [
                outbox
                "${home}/.claude/channels/discord/inbox"
                store
                # Its threads' scratch folders and its working areas, where its sessions write their results.
                "${home}/scratch"
              ]
              ++ lib.filter (directory: directory != outbox) config.butler.writePaths
              # Butler's own files attach_file and mac push read, as Aaron asked on 6 Nov 2026, but for the sensitive ones below.
              ++ lib.filter (directory: directory != store) config.butler.attach.readPaths
            ))
            (lib.concatStringsSep ":" config.butler.attach.sensitivePaths)
          ]
          (builtins.readFile ./butler-assets/asset.py)
      );

  reads = [
    "interactive"
    "cron"
    "call"
  ];
  writes = [
    "interactive"
    "cron"
  ];
in
{
  options.butler.assets.package = lib.mkOption {
    description = "The asset command, which imagine and render call to save what they make in butler's asset store.";
    type = lib.types.package;
    readOnly = true;
    default = asset;
  };

  config = {
    systemd.tmpfiles.rules = [ "d ${store} 0700 butler butler -" ];

    butler.commands.asset = {
      package = asset;
      description = ''
        Butler's shared asset store on spike: every picture, logo, deck and export made for Aaron, kept for good and found from any thread, call or scheduled run.
        asset add <path> <name> [description...] [--tags a,b] [--task words] [--kind kind] | asset list [words...] [--tag tag] | asset show <name> (prints its path and an outbox copy to attach) | asset remove <name>
        add copies from the outbox, Aaron's Discord attachments, the store, your documents, memory, working areas or scratch folders, never a hidden file, a secret or a sensitive document such as an identity document.
      '';
      rules = [
        {
          match = [
            "add"
            "**"
          ];
          lanes = writes;
          acts = true;
          flags = [
            "--tags"
            "--task"
            "--kind"
          ];
        }
        {
          match = [
            "list"
            "**"
          ];
          lanes = reads;
          flags = [ "--tag" ];
        }
        {
          match = [
            "show"
            "*"
          ];
          lanes = reads;
        }
        {
          match = [
            "remove"
            "*"
          ];
          lanes = [ "interactive" ];
          acts = true;
        }
      ];
      skill = ./butler-skills/assets;
    };
  };
}
