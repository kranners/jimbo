{
  config,
  lib,
  pkgs,
  ...
}:
let
  python = pkgs.python3Packages;
  home = config.users.users.butler.home;

  # `mac <host> fetch` copies a file from a Mac's or jimbo's ~/Downloads or ~/butler-drop into this spool, under the
  # ~/.cache butler's Read is denied, and butler-index-drop moves it into the index inbox the daemon cannot write.
  drop = "${home}/.cache/index-drop";
  dropMax = 500 * 1024 * 1024;
  inbox = "/var/lib/butler-index/inbox";

  # Run as butler outside the daemon's sandbox: each spooled `<folder>--<name>` lands in inbox/<folder> only when
  # that folder already exists, is not the browser agents' own, and the file is a plain file under the cap; a
  # messages snapshot must also be a sound `<device>-messages.sqlite` with Messages' tables, as the agents' drop asks.
  dropMover = pkgs.writeShellApplication {
    name = "butler-index-drop";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.findutils
      pkgs.sqlite
    ];
    text = ''
            spool=${drop}/spool results=${drop}/results
            folders='^[a-z0-9]+(-[a-z0-9]+)*$'
            names='^[A-Za-z0-9][A-Za-z0-9._ ()+,-]{0,199}$'
            snapshots='^[a-z0-9]+-messages[.]sqlite$'
            mkdir -p "$results"
            find "$results" -type f -mmin +1440 -delete
            shopt -s nullglob
            # A fetch of several files spools them seconds apart, so settle a moment and keep going until the spool
            # stays empty, taking a whole burst in one run instead of one start per file.
            while sleep 2; entries=("$spool"/*); [ ''${#entries[@]} -gt 0 ]; do
            for entry in "''${entries[@]}"; do
              base=''${entry##*/}
              folder=''${base%%--*} name=''${base#*--}
              verdict=""
              if [ -L "$entry" ] || [ ! -f "$entry" ]; then
                verdict="not a plain file"
              elif [ "$folder" = "$base" ] || ! [[ "$folder" =~ $folders ]] || ! [[ "$name" =~ $names ]]; then
                verdict="a bad folder or file name"
              elif [ "$folder" = browser ] || [ ! -d "${inbox}/$folder" ]; then
                verdict="the index inbox has no folder $folder it takes files in"
              elif [ "$(stat -c %s "$entry")" -gt ${toString dropMax} ]; then
                verdict="over the ${toString (dropMax / 1024 / 1024)} MB limit"
              elif [ "$folder" = messages ] && ! [[ "$name" =~ $snapshots ]]; then
                verdict="a messages snapshot is named <device>-messages.sqlite, the device in lowercase letters and digits"
              elif [ "$folder" = messages ] && { [ "$(sqlite3 "file:$entry?mode=ro" "PRAGMA quick_check" 2>&1)" != ok ] ||
                [ "$(sqlite3 "file:$entry?mode=ro" "SELECT count(*) FROM sqlite_master WHERE type = 'table' AND name IN ('message', 'handle', 'chat', 'chat_message_join')" 2>&1)" != 4 ]; }; then
                verdict="not a sound Messages snapshot"
              fi
              if [ -n "$verdict" ]; then
                rm -f -- "$entry"
                echo "refused $base: $verdict"
                printf 'refused %s
      ' "$verdict" > "$results/.$base" && mv -f "$results/.$base" "$results/$base"
                continue
              fi
              chmod 600 "$entry"
              # ReadWritePaths bind each folder apart, so the move out of the spool is a copy; it lands as a partial in the
              # inbox's root, as the browser agents' drop does, and only the rename within the inbox reaches the ingest.
              partial="${inbox}/.drop-$folder-$name.partial"
              mv -f -- "$entry" "$partial"
              mv -f -- "$partial" "${inbox}/$folder/$name"
              echo "moved $base into inbox/$folder"
              printf 'ok %s/%s
      ' "$folder" "$name" > "$results/.$base" && mv -f "$results/.$base" "$results/$base"
            done
            done
    '';
  };

  peer =
    name: lib.findFirst (peer: peer.name == name) null config.networking.wireguard.interfaces.wg0.peers;
  addressOf = name: lib.removeSuffix "/32" (lib.head (peer name).allowedIPs);

  hosts = {
    pilot = {
      os = "macos";
      address = addressOf "pilot";
      user = "aaronpierce";
    };
    piggys-MBP = {
      os = "macos";
      address = addressOf "piggys-MBP";
      user = "aaron";
    };
    # The jimbo PC dual boots, so it answers as whichever install is up. Its Linux install joins once spike has its
    # WireGuard key, `jimbo` in ./wireguard.nix.
    jimbo.systems =
      lib.optional (peer "jimbo" != null) {
        os = "linux";
        address = addressOf "jimbo";
        user = "aaron";
      }
      ++ [
        {
          os = "windows";
          address = addressOf "windows";
          user = "aaron";
        }
      ];
  };

  substitutions = {
    "@hosts@" = builtins.toJSON hosts;
    "@ssh@" = lib.getExe pkgs.openssh;
    "@ffmpeg@" = lib.getExe pkgs.ffmpeg-headless;
    "@outbox@" = "${config.users.users.butler.home}/outbox";
    "@windowsScreenshot@" = "${../../../docs/windows-screenshot.ps1}";
    "@helperPort@" = toString (import ../../butler-access/helper.nix).port;
    "@memoryAudit@" = lib.getExe config.butler.memoryAudit;
    "@expected@" = config.butler.monitor.expectedDir;
    "@idle@" = toString (import ../../butler-access/overlay/settings.nix).idle;
    "@drop@" = drop;
    "@dropMax@" = toString dropMax;
  };

  mac =
    pkgs.writers.writePython3Bin "mac"
      {
        libraries = [
          python.vncdotool
          python.pillow
        ];
        flakeIgnore = [ "E501" ];
      }
      (
        builtins.replaceStrings (lib.attrNames substitutions) (lib.attrValues substitutions) (
          builtins.readFile ./butler-mac/mac.py
        )
      );
in
{
  butler.commands.mac = {
    package = mac;
    description = ''
      See and drive Aaron's MacBooks, pilot and piggys-MBP, and his dual-boot PC jimbo, as he watches: his real screen, mouse and keyboard over VNC, and a shell over ssh.
      mac hosts | mac log [count] | mac <host> look | mac <host> say [text] (or text on stdin) | mac <host> done | mac <host> click <x> <y> [left|right|middle|double] | mac <host> move <x> <y> | mac <host> drag <x1> <y1> <x2> <y2> | mac <host> scroll <x> <y> <up|down> [clicks] | mac <host> type [text] (or text on stdin) | mac <host> key <combo> [combo...] | mac <host> windows | mac <host> run [shell words] (or a script on stdin, for anything with a dash) | mac <host> record start | mac <host> record stop | mac <host> keepawake [status|on|off] | mac <host> sleep | mac jimbo boot <linux|windows> [confirm]
      jimbo runs NixOS with Hyprland or Windows, one at a time: mac hosts says which is up, run takes sh on Linux and PowerShell on Windows, it has no cmd key (use ctrl and super), and boot restarts it into the other only when Aaron asks, never past a login or disk-encryption screen.
      windows lists the front app, the running apps and every window front to back with its place and size, so you can open, focus, switch, resize, minimise, close and quit apps and windows; the mac skill has the recipes.
      On the Macs: mac <host> menu <app|front> [menu] [item...] | mac <host> dialog [app] | mac <host> press <number|name> [app] | mac <host> focus <number|name> [app] | mac <host> displays | mac <host> display <n> [look] | mac <host> display <n> click <x> <y> [left|right|double] | mac <host> window <rectangle action> | mac <host> window display <n>
      menu lists an app's menus or chooses an item by name, dialog numbers the front window's buttons and fields for press and focus, displays and display see and click every screen, not just the main one look shows, and window snaps or moves the front window with Rectangle; the only stop is a password or Touch ID prompt, which goes to Aaron.
      keepawake on holds the machine awake and unlocked, keepawake off lets it idle-sleep and lock as usual, and sleep turns it off and sleeps it now.
      While you drive pilot or piggys-MBP you appear on its screen, top right, with up to three speech bubbles: say puts your own short narration in one, and done hands control back and fades you out, as does a minute and a half without a mac command. Every action and bubble is kept in an audit log in your memory, audit/mac.
      fetch copies one file, at most 500 MB, from piggys-MBP's or jimbo's ~/Downloads or ~/butler-drop into spike's index inbox folder, such as exports or messages, for the ingest; never from pilot. A bare file name is in ~/Downloads, and name renames it.
      Every action but say, done, fetch, windows, run, record, keepawake, sleep and boot prints the outbox path of a fresh screenshot to read or attach with attach_file; x and y are pixels of that picture.
    '';
    stdin = true;
    # Egress, so in a thread that has read private data or began as a voice request or board message the first action asks Aaron once for the `mac` area, and the rest run unasked.
    # An action the daemon's mac checker reads as an outcome, anything on pilot beyond reading, a `run` that would send or delete, a Send-like control or a `confirm`, asks every time.
    rules = [
      {
        match = [ "**" ];
        lanes = [ "interactive" ];
        egress = true;
        grant = "mac";
        outcomes = "mac";
      }
    ];
    credentials.butler-mac-key = "/var/lib/secrets/butler-mac-key";
    skill = ./butler-skills/mac;
  };

  # The private flake's ingest makes and reads the inbox's exports folder, where statements and service exports go.
  systemd.tmpfiles.rules = [
    "d ${home}/.cache 0700 butler butler -"
    "d ${drop} 0700 butler butler -"
    "d ${drop}/spool 0700 butler butler -"
    "d ${drop}/partial 0700 butler butler -"
    "d ${drop}/results 0700 butler butler -"
  ];

  # A burst of fetches starts the mover once per file; with systemd's default start limit, 5 in 10 seconds, the fifth
  # failed both units with start-limit-hit, and no later drop was moved until they were reset. Neither has a limit now.
  systemd.paths.butler-index-drop = {
    wantedBy = [ "paths.target" ];
    unitConfig.StartLimitIntervalSec = 0;
    pathConfig = {
      DirectoryNotEmpty = "${drop}/spool";
      TriggerLimitIntervalSec = 0;
    };
  };

  # A switch clears a failed state left by an earlier one, so landing brings the drop back without a hand reset.
  system.activationScripts.butler-index-drop-reset = {
    deps = [ "etc" ];
    text = ''
      ${config.systemd.package}/bin/systemctl reset-failed butler-index-drop.path butler-index-drop.service 2>/dev/null || true
    '';
  };

  systemd.services.butler-index-drop = {
    description = "Move the files butler fetched from the Macs into its index inbox";
    unitConfig.StartLimitIntervalSec = 0;
    serviceConfig = {
      Type = "oneshot";
      User = "butler";
      Group = "butler";
      ExecStart = lib.getExe dropMover;
      UMask = "0077";
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      PrivateNetwork = true;
      NoNewPrivileges = true;
      ReadWritePaths = [
        drop
        inbox
      ];
    };
  };
}
