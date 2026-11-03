{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkOption types;
  cfg = config.butler.drop;

  root = "/var/lib/butler-drop";
  incoming = "${root}/incoming";
  # butler's own requests, in its home, which the daemon may write, for butler-drop-ingest to act on outside its sandbox.
  requests = "/var/lib/butler/drop/requests";
  results = "/var/lib/butler/drop/results";
  inbox = "/var/lib/butler-index/inbox";

  maxBytes = 2147483648;
  maxTotalBytes = 8589934592;
  maxFiles = 50;
  readBytes = 40000;
  namePattern = "^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$";

  # The index's export folders a drop may go into, those of kranners/butler's index.nix but browser and messages,
  # whose own drop checks every snapshot; a reader added there needs its folder added here too.
  sources = [
    "amazon"
    "claude"
    "discord"
    "facebook"
    "garmin"
    "gphotos"
    "hevy"
    "instagram"
    "location"
    "messenger-e2ee"
    "paypal"
    "spotify"
    "steam"
    "takeout"
    "uber"
  ];

  # The forced command of every drop key: it writes stdin to the file SSH_ORIGINAL_COMMAND names, and nothing else.
  receive = pkgs.writeShellApplication {
    name = "butler-drop-receive";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      name="''${SSH_ORIGINAL_COMMAND:-}"
      if ! [[ "$name" =~ ${namePattern} ]] || [[ "$name" == *.partial ]]; then
        echo "refused: give one file name of letters, digits, dots, dashes and underscores" >&2
        exit 64
      fi
      umask 027
      shopt -s nullglob
      held=(${incoming}/*)
      [ -e "${incoming}/$name" ] || [ "''${#held[@]}" -lt ${toString maxFiles} ] \
        || { echo "refused: the drop folder already holds ${toString maxFiles} files" >&2; exit 65; }
      partial="${incoming}/.$name.partial"
      trap 'rm -f "$partial"' EXIT
      head -c $((${toString maxBytes} + 1)) > "$partial"
      size=$(stat -c %s "$partial")
      [ "$size" -le ${toString maxBytes} ] || { echo "refused: over 2 GiB" >&2; exit 65; }
      total=$(du -sb ${incoming} | cut -f1)
      [ "$total" -le ${toString maxTotalBytes} ] || { echo "refused: the drop folder would hold over 8 GiB" >&2; exit 65; }
      mv -f "$partial" "${incoming}/$name"
      echo "dropped $name ($size bytes)"
    '';
  };

  drop = pkgs.writeShellApplication {
    name = "drop";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.findutils
      pkgs.gnugrep
      pkgs.jq
      pkgs.libarchive
    ];
    text = ''
      usage() {
        echo "usage: drop ls | drop sources | drop read <file> [<member>] | drop ingest <file> <source> | drop delete <file>" >&2
        exit 2
      }

      file_arg() {
        [[ "$1" =~ ${namePattern} ]] && [[ "$1" != *.partial ]] || { echo "drop: not a drop file name: $1" >&2; exit 2; }
        [ -f "${incoming}/$1" ] || { echo "drop: no $1 in the drop folder; drop ls lists it" >&2; exit 1; }
      }

      request() {
        id="$(date +%s%N)-$$"
        jq -n --arg action "$1" --arg file "$2" --arg source "''${3:-}" '{action: $action, file: $file, source: $source}' \
          > "${requests}/.$id.tmp"
        mv "${requests}/.$id.tmp" "${requests}/$id.json"
        for _ in $(seq 60); do
          if [ -f "${results}/$id" ]; then
            cat "${results}/$id"
            ok=$(head -c 3 "${results}/$id")
            rm -f "${results}/$id"
            [ "$ok" = "ok:" ]
            exit
          fi
          sleep 0.5
        done
        echo "drop: queued, but spike has not acted on it within 30 seconds; drop ls shows whether the file is still waiting" >&2
        exit 75
      }

      [ $# -ge 1 ] || usage
      case "$1" in
        ls)
          [ $# -eq 1 ] || usage
          [ -d ${incoming} ] || { echo "drop: the drop folder is missing" >&2; exit 1; }
          find ${incoming} -maxdepth 1 -type f ! -name '.*' -printf '%TY-%Tm-%Td %TH:%TM  %12s  %f\n' | sort
          ;;
        sources)
          [ $# -eq 1 ] || usage
          printf '%s\n' ${lib.escapeShellArgs sources}
          ;;
        read)
          [ $# -eq 2 ] || [ $# -eq 3 ] || usage
          file_arg "$2"
          path="${incoming}/$2"
          if [ $# -eq 3 ]; then
            bsdtar -xOf "$path" -- "$3" | head -c ${toString readBytes}
          elif bsdtar -tf "$path" > /dev/null 2>&1; then
            echo "$2 is an archive; drop read $2 <member> prints one member:"
            bsdtar -tvf "$path" | head -c ${toString readBytes}
          else
            head -c ${toString readBytes} "$path"
          fi
          ;;
        ingest)
          [ $# -eq 3 ] || usage
          file_arg "$2"
          printf '%s\n' ${lib.escapeShellArgs sources} | grep -qxF -- "$3" \
            || { echo "drop: $3 is not a source the index reads; drop sources lists them" >&2; exit 2; }
          request ingest "$2" "$3"
          ;;
        delete)
          [ $# -eq 2 ] || usage
          file_arg "$2"
          request delete "$2"
          ;;
        *) usage ;;
      esac
    '';
  };

  # Runs as butler outside the daemon's sandbox, which sees the drop folder read-only and the inbox not at all.
  ingest = pkgs.writeShellApplication {
    name = "butler-drop-ingest";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.jq
    ];
    text = ''
      umask 077
      shopt -s nullglob
      for req in ${requests}/*.json; do
        id=$(basename "$req" .json)
        action=$(jq -r '.action // ""' "$req" 2> /dev/null || true)
        file=$(jq -r '.file // ""' "$req" 2> /dev/null || true)
        source=$(jq -r '.source // ""' "$req" 2> /dev/null || true)
        rm -f "$req"
        result=
        if ! [[ "$file" =~ ${namePattern} ]] || [[ "$file" == *.partial ]] || ! [ -f "${incoming}/$file" ]; then
          result="failed: no such drop file"
        elif [ "$action" = delete ]; then
          rm -f "${incoming}/$file"
          result="ok: deleted $file"
        elif [ "$action" = ingest ] && printf '%s\n' ${lib.escapeShellArgs sources} | grep -qxF -- "$source" \
          && [ -d "${inbox}/$source" ]; then
          partial="${inbox}/.drop-$file.partial"
          if cp --no-preserve=all "${incoming}/$file" "$partial" && mv -f "$partial" "${inbox}/$source/$file"; then
            rm -f "${incoming}/$file"
            result="ok: moved $file into the index's $source folder, which ingests it within minutes; it is gone from the drop folder"
          else
            rm -f "$partial"
            result="failed: could not copy $file into the index's $source folder"
          fi
        else
          result="failed: not a request spike takes"
        fi
        printf '%s\n' "$result" > "${results}/.$id.tmp"
        mv "${results}/.$id.tmp" "${results}/$id"
        echo "$id $action $source: $result"
      done
    '';
  };

  dropKeys = lib.concatLists (
    lib.mapAttrsToList (
      _: device:
      lib.optionals device.enable (
        map (key: ''restrict,from="${device.address}",command="${lib.getExe receive}" ${key}'') device.keys
      )
    ) cfg.devices
  );
in
{
  options.butler.drop.devices = mkOption {
    type = types.attrsOf (
      types.submodule {
        options = {
          enable = mkOption {
            type = types.bool;
            default = false;
          };
          address = mkOption {
            type = types.str;
            description = "The one address the device's keys may connect from, its WireGuard peer's";
          };
          keys = mkOption {
            type = types.listOf types.str;
            default = [ ];
            description = "The public halves of the device's drop keys, each made on the device by its butler-drop helper";
          };
        };
      }
    );
    default = { };
    description = "Devices that may push export files into butler's drop folder, and only that";
  };

  config = {
    butler.drop.devices = {
      piggys-MBP = {
        enable = true;
        address = "10.100.0.2";
        # Paste the output of `butler-drop --key` on piggys-MBP here.
        keys = [ ];
      };
      # The employer's Mac, which butler uses only for the tasks Aaron names, so it may not drop until he turns it on.
      pilot = {
        enable = false;
        address = "10.100.0.11";
      };
    };

    users.users.butler-drop = {
      isSystemUser = true;
      group = "butler-drop";
      useDefaultShell = true;
      openssh.authorizedKeys.keys = dropKeys;
    };
    users.groups.butler-drop = { };

    # The key's own restrictions, repeated for the user, so no key added for it by hand gets a shell or a forward either.
    services.openssh.extraConfig = ''
      Match User butler-drop
        ForceCommand ${lib.getExe receive}
        PermitTTY no
        AllowTcpForwarding no
        AllowStreamLocalForwarding no
        AllowAgentForwarding no
        X11Forwarding no
        PermitTunnel no
        PermitUserRC no
    '';

    systemd.tmpfiles.rules = [
      "d ${root} 0750 butler-drop butler -"
      # butler's group, there for butler-drop-ingest alone, since the daemon sees it read-only; unread drops age out.
      "d ${incoming} 2770 butler-drop butler 7d"
      "d /var/lib/butler/drop 0700 butler butler -"
      "d ${requests} 0700 butler butler -"
      "d ${results} 0700 butler butler 1d"
    ];

    systemd.services.butler.serviceConfig.BindReadOnlyPaths = [ "-${incoming}" ];

    systemd.paths.butler-drop-ingest = {
      wantedBy = [ "multi-user.target" ];
      pathConfig.DirectoryNotEmpty = requests;
    };

    systemd.services.butler-drop-ingest = {
      description = "Move or delete butler's dropped files on its requests";
      serviceConfig = {
        Type = "oneshot";
        User = "butler";
        Group = "butler";
        ExecStart = lib.getExe ingest;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateNetwork = true;
        NoNewPrivileges = true;
        ReadWritePaths = [
          incoming
          requests
          results
          inbox
        ];
      };
    };

    butler.commands.drop = {
      package = drop;
      private = true;
      description = ''
        Files Aaron pushed from piggys-MBP with butler-drop, such as his account exports: list them, read one, move one into the index's inbox folder for its source, or delete it.
        drop ls | drop sources | drop read <file> [<member of an archive>] | drop ingest <file> <source> | drop delete <file>
        Reads print at most 40,000 bytes; an archive read without a member lists its members.
      '';
      rules = [
        {
          match = [ "ls" ];
          lanes = [
            "interactive"
            "cron"
          ];
        }
        {
          match = [ "sources" ];
          lanes = [
            "interactive"
            "cron"
          ];
        }
        {
          match = [
            "read"
            "**"
          ];
          lanes = [
            "interactive"
            "cron"
          ];
        }
        {
          match = [
            "ingest"
            "**"
          ];
          lanes = [ "interactive" ];
          acts = true;
        }
        {
          match = [
            "delete"
            "**"
          ];
          lanes = [ "interactive" ];
          acts = true;
        }
      ];
    };
  };
}
