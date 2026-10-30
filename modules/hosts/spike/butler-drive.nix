{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.users.users.butler) home;

  rcloneDirectory = "${home}/.config/rclone";
  rcloneConfig = "${rcloneDirectory}/rclone.conf";

  textLimit = 40000;
  pdfLimit = 20 * 1024 * 1024;

  both = [
    "interactive"
    "cron"
  ];

  rclone = "${lib.getExe pkgs.rclone} --config ${rcloneConfig} --drive-export-formats txt,csv --log-level ERROR";

  drive = pkgs.writeShellApplication {
    name = "drive";

    runtimeInputs = [
      pkgs.coreutils
      pkgs.jq
      pkgs.poppler-utils
    ];

    text = ''
      usage() {
        echo "usage: drive ls [folder path]" >&2
        echo "       drive search <words>..." >&2
        echo "       drive cat <file path>" >&2
        echo "       drive cat <folder id> <name>  (a search result)" >&2
        exit 2
      }

      rclone() {
        ${rclone} "$@"
      }

      [ $# -ge 1 ] || usage

      case "$1" in
        ls)
          [ $# -le 2 ] || usage
          rclone lsjson "drive:''${2:-}" \
            | jq --raw-output 'sort_by((.IsDir | not), .Path) | .[:200][] | [(if .IsDir then "folder" else .MimeType end), (if .Size < 0 then "-" else .Size end), .ModTime[0:10], .Path] | @tsv'
          ;;
        search)
          [ $# -ge 2 ] || usage
          shift
          words="$*"
          words=''${words//\\/\\\\}
          words=''${words//\'/\\\'}
          rclone backend query drive: "fullText contains '$words' and trashed = false and mimeType != 'application/vnd.google-apps.folder'" \
            | jq --raw-output '
                {"application/vnd.google-apps.document": ".txt", "application/vnd.google-apps.spreadsheet": ".csv", "application/vnd.google-apps.presentation": ".txt"} as $exported
                | sort_by(.modifiedTime) | reverse | .[:25][]
                | [(.parents[0] // "shared"), .name + ($exported[.mimeType] // ""), .mimeType, .modifiedTime[0:10]] | @tsv'
          ;;
        cat)
          case $# in
            2) remote="drive:$2" ;;
            3)
              [[ $2 =~ ^[A-Za-z0-9_-]+$ ]] || usage
              if [ "$2" = shared ]; then
                remote="drive,shared_with_me:$3"
              else
                remote="drive,root_folder_id=$2:$3"
              fi
              ;;
            *) usage ;;
          esac

          file=$(rclone lsjson --stat "$remote")
          mime=$(jq --raw-output .MimeType <<<"$file")
          size=$(jq --raw-output .Size <<<"$file")
          text=$(mktemp)
          trap 'rm -f "$text" "$text.pdf"' EXIT

          case "$mime" in
            text/* | application/json | application/xml)
              rclone cat --count ${toString (textLimit + 1)} "$remote" >"$text"
              ;;
            application/pdf)
              if [ "$size" -gt ${toString pdfLimit} ]; then
                echo "drive: the PDF is over ${
                  toString (pdfLimit / 1024 / 1024)
                } MB, too large to read" >&2
                exit 1
              fi
              rclone cat "$remote" >"$text.pdf"
              pdftotext -enc UTF-8 "$text.pdf" "$text"
              ;;
            *)
              echo "drive: a $mime file is not text, so it can only be listed" >&2
              exit 1
              ;;
          esac

          head --bytes ${toString textLimit} "$text"
          if [ "$(wc --bytes <"$text")" -gt ${toString textLimit} ]; then
            printf '\n[cut off after the first %s bytes]\n' ${toString textLimit}
          fi
          ;;
        *) usage ;;
      esac
    '';
  };

  butler-drive-login = pkgs.writeShellApplication {
    name = "butler-drive-login";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.rclone
    ];
    text = ''
      if [ "$(id -un)" != butler ]; then
        echo "run it as butler: sudo -u butler butler-drive-login" >&2
        exit 1
      fi

      read -r -p "Google OAuth client ID: " client_id
      read -r -s -p "Google OAuth client secret: " client_secret
      echo

      umask 077
      echo "Open the link rclone prints in a browser on the machine whose port 53682 is forwarded here."
      rclone --config ${rcloneConfig} config create drive drive \
        scope=drive.readonly client_id="$client_id" client_secret="$client_secret"
      rclone --config ${rcloneConfig} about drive:
    '';
  };
in
{
  options.butler.drive.enable = lib.mkEnableOption "butler's read-only Google Drive tool, once butler-drive-login has written its rclone config";

  config = lib.mkIf config.butler.drive.enable {
    environment.systemPackages = [ butler-drive-login ];

    systemd.tmpfiles.rules = [
      "d ${home}/.config 0700 butler butler -"
      "d ${rcloneDirectory} 0700 butler butler -"
    ];

    butler.commands.drive = {
      package = drive;
      description = ''
        Read Aaron's Google Drive, read-only: list a folder, search every file he can see, and read text, Google Docs, Sheets (as CSV), Slides and PDFs as plain text.
        drive ls [folder path] | drive search <words>... | drive cat <file path> | drive cat <folder id> <name> (the first two columns of a search result)
      '';
      rules = [
        {
          match = [
            "ls"
            "**"
          ];
          lanes = both;
        }
        {
          match = [
            "search"
            "**"
          ];
          lanes = both;
          taints = true;
        }
        {
          match = [
            "cat"
            "**"
          ];
          lanes = both;
          taints = true;
        }
      ];
      skill = ./butler-skills/drive;
    };
  };
}
