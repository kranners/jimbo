{
  config,
  pkgs,
  lib,
  ...
}:
let
  credential = name: "/run/credentials/butler.service/${name}";
  secret = name: "/var/lib/secrets/butler-${name}";

  both = [
    "interactive"
    "cron"
  ];
  interactive = [ "interactive" ];

  toml = pkgs.formats.toml { };

  mailAccounts = config.butler.mail.accounts;
  sendingAccounts = lib.attrNames (
    lib.filterAttrs (_: account: account.himalaya ? smtp) mailAccounts
  );

  # The reading actions' options, which may stand where the daemon's rules otherwise refuse an argument starting with -.
  folderFlags = [
    "--folder"
    "--all-folders"
  ];

  mailPassword = name: "email-${name}-password";

  # Aaron's work Google account is read through the Gmail API, read-only, by butler-work-google.nix's reader.
  workGoogle = config.butler.workGoogle.enable;
  workReader = lib.getExe' config.butler.workGoogle.package "work-google";

  passwordLogin = name: address: {
    username = address;
    password.command = "${pkgs.coreutils}/bin/cat ${credential (mailPassword name)}";
  };

  passwordAccount =
    {
      name,
      address,
      imapServer,
      smtpServer,
      mailbox,
      saveSent ? false,
    }:
    {
      himalaya = {
        email = address;
        display-name = "Aaron Pierce";
        imap.server = imapServer;
        imap.sasl.plain = passwordLogin name address;
        smtp.server = smtpServer;
        smtp.sasl.plain = passwordLogin name address;
        mailbox.alias = mailbox;
      }
      // lib.optionalAttrs saveSent { message.send.save-copy = "sent"; };
      credentials.${mailPassword name} = secret (mailPassword name);
    };

  himalayaConfig = toml.generate "himalaya.toml" {
    accounts = lib.mapAttrs (_: account: account.himalaya) mailAccounts;
  };

  himalaya = "${pkgs.himalaya}/bin/himalaya --config ${himalayaConfig} --log-level off";

  mail = pkgs.writeShellApplication {
    name = "mail";

    runtimeInputs = [ pkgs.jq ];

    text = ''
      usage() {
        echo "usage: mail accounts" >&2
        echo "       mail unread-counts" >&2
        echo "       mail <account> mailboxes" >&2
        echo "       mail <account> [<folder>] unread [count]" >&2
        echo "       mail <account> [<folder>] list [count]" >&2
        echo "       mail <account> [<folder>] search <query>..." >&2
        echo "       mail <account> [<folder>] read <id>" >&2
        echo "       mail <account> archive <id>...  (from the inbox)" >&2
        echo "  <folder> is a folder's name, such as junk, spam, archive or clutter, or all-folders for unread, list and search;" >&2
        echo "  --folder <name> and --all-folders after the action do the same" >&2
        ${lib.optionalString workGoogle ''echo "       mail work unread [count] | list [count] | search <words>... | read <id>  (read-only)" >&2''}
        exit 2
      }

      # himalaya prints its errors to stdout, which the daemon drops when a command fails, so a failure's output goes to stderr instead.
      himalaya() {
        local output status=0
        output=$(${himalaya} "$@") || status=$?
        if [ "$status" -ne 0 ]; then
          printf '%s\n' "$output" >&2
          return "$status"
        fi
        printf '%s\n' "$output"
      }

      # Plain words, not himalaya's query language, search the subject, sender and body for them as one phrase.
      search_query() {
        case "$1" in
          date | after | from | to | subject | body | flag | not | order | "(" | "("*) printf '%s\0' "$@" ;;
          *)
            local phrase="$*"
            phrase=''${phrase//\\/\\\\}
            phrase=''${phrase//\"/\\\"}
            printf '%s\0' subject "\"$phrase\"" or from "\"$phrase\"" or body "\"$phrase\"" order by date desc
            ;;
        esac
      }

      # A folder named loosely, such as junk, spam or archive, is matched to the account's own: by name, then case, role, the last part of its path, and junk and spam as one.
      resolve_folder() {
        local boxes id
        boxes=$(himalaya --json --account "$account" mailbox list) || exit
        id=$(jq -r --arg want "$1" '
          def low: ascii_downcase;
          def leaf: split("/") | last;
          def junky: test("^(junk|spam|junk e-?mail|bulk( mail)?)$");
          ($want | low) as $w
          | .mailboxes as $m
          | [$m[] | select(.name == $want)]
            + [$m[] | select((.name | low) == $w)]
            + [$m[] | select(((.role // "") | low) == $w)]
            + [$m[] | select((.name | leaf | low) == $w)]
            + (if $w | junky then [$m[] | select(((.role // "") | low) == "junk" or (.name | leaf | low | junky))] else [] end)
          | .[0].id // empty' <<<"$boxes")
        if [ -z "$id" ]; then
          echo "mail: $account has no folder \"$1\"; its folders are: $(jq -r '[.mailboxes[].name] | join(", ")' <<<"$boxes")" >&2
          exit 2
        fi
        printf '%s\n' "$id"
      }

      # Lists or searches every folder, the inbox first, one table with each message's folder, a message in several folders, as Gmail's labels put it, shown once.
      every_folder() {
        local verb="$1" boxes id out results="" failed=()
        shift
        boxes=$(himalaya --json --account "$account" mailbox list) || exit
        mapfile -t ids < <(jq -r '.mailboxes | map(select(((.role // "") | ascii_downcase) == "inbox")) + map(select(((.role // "") | ascii_downcase) != "inbox")) | .[].id' <<<"$boxes")
        for id in "''${ids[@]}"; do
          if out=$(${himalaya} --json --account "$account" envelope "$verb" --mailbox "$id" "$@" 2>/dev/null); then
            results+=$(jq -c --arg folder "$id" '.envelopes[] | . + {folder: $folder}' <<<"$out")$'\n'
          else
            failed+=("$id")
          fi
        done
        jq -rs '
          def who: if type == "array" then map(if type == "object" then .name // .email else . end) | join(", ") elif type == "object" then .name // .email else . // "" end;
          def flags: [(.flags // [])[] | if type == "object" then .iana // .raw else . end | tostring] | join(",");
          reduce .[] as $e ({seen: {}, out: []};
            ($e["message-id"] // "\($e.folder)/\($e.id)") as $key
            | if .seen[$key] then . else .seen[$key] = true | .out += [$e] end)
          | .out
          | if length == 0 then "No messages found in any folder."
            else (["FOLDER", "ID", "FLAGS", "DATE", "FROM", "SUBJECT"] | @tsv), (.[] | [.folder, (.id | tostring), flags, (.date // "" | tostring), (.from | who), (.subject // "")] | @tsv)
            end' <<<"$results"
        if [ ''${#failed[@]} -gt 0 ]; then
          echo "Could not read: $(IFS=,; echo "''${failed[*]}")"
        fi
        echo "Read one with: mail $account <folder> read <id>"
      }

      [ $# -ge 1 ] || usage

      if [ "$1" = accounts ]; then
        himalaya account list
        ${lib.optionalString workGoogle ''echo "work (work Google account, read-only)"''}
        exit
      fi

      ${lib.optionalString workGoogle ''
        if [ "$1" = work ]; then
          shift
          for argument in "$@"; do
            case "$argument" in
              -*) usage ;;
            esac
          done
          exec ${workReader} mail "$@"
        fi
      ''}

      if [ "$1" = unread-counts ]; then
        for account in ${lib.escapeShellArgs (lib.attrNames mailAccounts)}; do
          if count=$(himalaya --json --account "$account" envelope search --page-size 1000 not flag seen | jq '.envelopes | length'); then
            echo "$account $count"
          else
            echo "$account unavailable"
          fi
        done
        ${lib.optionalString workGoogle ''
          if count=$(${workReader} mail unread-count); then
            echo "work $count"
          else
            echo "work unavailable"
          fi
        ''}
        exit
      fi

      [ $# -ge 2 ] || usage
      account="$1"
      shift
      case "$account" in
        -*) usage ;;
      esac

      # A folder may come before a reading action, such as `mail outlook junk list 5`, since the daemon's rules refuse most arguments starting with -.
      folder=""
      case "$1" in
        mailboxes | unread | list | search | read) ;;
        *)
          case "''${2:-}" in
            unread | list | search | read)
              folder="$1"
              shift
              ;;
          esac
          ;;
      esac
      action="$1"
      shift

      arguments=()
      case "$action" in
        unread | list | search | read)
          while [ $# -gt 0 ]; do
            case "$1" in
              --folder)
                [ $# -ge 2 ] && [ -z "$folder" ] || usage
                folder="$2"
                shift 2
                ;;
              --all-folders)
                [ -z "$folder" ] || usage
                folder=all-folders
                shift
                ;;
              *)
                arguments+=("$1")
                shift
                ;;
            esac
          done
          ;;
        *) arguments=("$@") ;;
      esac
      set -- "''${arguments[@]}"

      for argument in "$folder" "$@"; do
        case "$argument" in
          -*) usage ;;
        esac
      done

      everywhere=false
      mailbox=()
      case "$folder" in
        "") ;;
        all-folders | all)
          [ "$action" != read ] || usage
          everywhere=true
          ;;
        *)
          folder=$(resolve_folder "$folder")
          mailbox=(--mailbox "$folder")
          echo "Folder: $folder"
          ;;
      esac

      case "$action" in
        mailboxes) himalaya --account "$account" mailbox list ;;
        unread)
          if $everywhere; then
            every_folder search --page-size "''${1:-10}" not flag seen order by date desc
          else
            himalaya --account "$account" envelope search "''${mailbox[@]}" --page-size "''${1:-10}" not flag seen order by date desc
          fi
          ;;
        list)
          if $everywhere; then
            every_folder list --page-size "''${1:-10}"
          else
            himalaya --account "$account" envelope list "''${mailbox[@]}" --page-size "''${1:-10}"
          fi
          ;;
        search)
          [ $# -ge 1 ] || usage
          mapfile -d "" -t query < <(search_query "$@")
          if $everywhere; then
            every_folder search --page-size 10 "''${query[@]}"
          else
            himalaya --account "$account" envelope search "''${mailbox[@]}" "''${query[@]}"
          fi
          ;;
        read)
          [ $# -eq 1 ] || usage
          if ! himalaya --account "$account" message read "''${mailbox[@]}" "$1"; then
            [ -n "$folder" ] || echo "mail: an id belongs to its folder; read a message from another folder as: mail $account <folder> read $1" >&2
            exit 1
          fi
          ;;
        archive) [ $# -ge 1 ] || usage; himalaya --account "$account" message move --to archive "$@" ;;
        *) usage ;;
      esac
    '';
  };

  subjectLimit = 200;
  approvalLimit = 1400;

  mail-send = pkgs.writeShellApplication {
    name = "mail-send";

    runtimeInputs = [
      pkgs.coreutils
      pkgs.jq
    ];

    text = ''
      usage() {
        echo "usage: mail-send <account> <to> <subject>  (subject at most ${toString subjectLimit} bytes, plain-text body on stdin)" >&2
        echo "accounts: ${lib.concatStringsSep ", " sendingAccounts}" >&2
        exit 2
      }

      [ $# -eq 3 ] || usage
      account="$1"
      to="$2"
      subject="$3"

      case "$account" in
        ${lib.concatStringsSep " | " sendingAccounts}) ;;
        *) usage ;;
      esac
      [[ $to =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]] || usage
      [[ -n $subject && $subject != *[$'\x01'-$'\x1f'$'\x7f']* ]] || usage
      [ "$(printf %s "$subject" | wc -c)" -le ${toString subjectLimit} ] || usage

      body=$(head -c ${toString (approvalLimit + 1)})
      [ -n "$body" ] || usage
      if [[ $body == *[$'\x01'-$'\x08'$'\x0b'-$'\x1f'$'\x7f']* ]]; then
        echo "mail-send: the body has control characters other than newlines and tabs; remove them" >&2
        exit 2
      fi
      approval=$(jq -n --indent 1 --arg account "$account" --arg to "$to" --arg subject "$subject" --arg body "$body" \
        '{args: [$account, $to, $subject], stdin: $body}' | wc -c)
      if [ "$approval" -gt ${toString approvalLimit} ]; then
        echo "mail-send: the body is too long for Aaron's approval to show all of it; shorten it" >&2
        exit 2
      fi

      printf '%s\n' "$body" | ${himalaya} --account "$account" message compose --to="$to" --subject="$subject" --send >/dev/null
      echo "Sent \"$subject\" to $to from $account"
    '';
  };

in
{
  options.butler.mail.accounts = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule {
        options = {
          himalaya = lib.mkOption { inherit (toml) type; };
          credentials = lib.mkOption {
            type = lib.types.attrsOf lib.types.str;
            default = { };
          };
        };
      }
    );
    default = { };
  };

  config.butler.mail.accounts = lib.mkIf config.butler.credentialedTools {
    fastmail = passwordAccount {
      name = "fastmail";
      address = "aaron@cute.engineer";
      imapServer = "imap.fastmail.com:993";
      smtpServer = "smtp.fastmail.com:465";
      mailbox = {
        inbox = "INBOX";
        archive = "Archive";
        sent = "Sent";
      };
      saveSent = true;
    };
    gmail = passwordAccount {
      name = "gmail";
      address = "aaronpierce114@gmail.com";
      imapServer = "imap.gmail.com:993";
      smtpServer = "smtp.gmail.com:465";
      mailbox = {
        inbox = "INBOX";
        archive = "[Gmail]/All Mail";
      };
    };
  };

  config.butler.commands = lib.mkMerge [
    (lib.mkIf (mailAccounts != { }) {
      mail = {
        package = mail;
        private = true;
        description = ''
            Read every folder of Aaron's email, Junk and Spam included, and archive from his inbox; it cannot delete or move mail anywhere else, and sends only through mail-send.
          mail accounts | mail unread-counts | mail <account> mailboxes | mail <account> [<folder>] unread [count] | mail <account> [<folder>] list [count] | mail <account> [<folder>] search <query>... | mail <account> [<folder>] read <id> | mail <account> archive <id>...
          <folder> is a folder's name, matched loosely, such as junk (Outlook's Junk, Gmail's Spam), archive or clutter, or all-folders for unread, list and search, such as mail outlook junk list 5 or mail outlook all-folders search aliexpress; an id belongs to its folder, so read it with the same folder. The inbox is the default.
          ${lib.optionalString workGoogle "mail work unread [count] | mail work list [count] | mail work search <Gmail search words>... | mail work read <id>: Aaron's work Google mail, read-only, in a conversation alone; it cannot archive or send."}
        '';
        rules = [
          {
            match = [ "accounts" ];
            lanes = both;
          }
          {
            match = [ "unread-counts" ];
            lanes = both;
          }
          {
            match = [
              "*"
              "mailboxes"
            ];
            lanes = both;
          }
        ]
        ++
          lib.concatMap
            (action: [
              {
                match = [
                  "*"
                  action
                  "**"
                ];
                lanes = both;
                flags = folderFlags;
              }
              # The same in a folder, such as `outlook junk list 5`.
              {
                match = [
                  "*"
                  "*"
                  action
                  "**"
                ];
                lanes = both;
                flags = folderFlags;
              }
            ])
            [
              "unread"
              "list"
              "search"
              "read"
            ]
        ++ [
          {
            match = [
              "*"
              "archive"
              "**"
            ];
            lanes = interactive;
            acts = true;
          }
        ];
        credentials = lib.mergeAttrsList (lib.catAttrs "credentials" (lib.attrValues mailAccounts));
        skill = ./butler-skills/email;
      };
    })

    (lib.mkIf (sendingAccounts != [ ]) {
      mail-send = {
        package = mail-send;
        description = ''
          Send a new plain-text email as Aaron, after he approves its exact recipient, subject and body with a button.
          mail-send <account> <to> <subject> (subject at most ${toString subjectLimit} bytes, body on stdin, about 1000 characters at most, less in short lines); accounts: ${lib.concatStringsSep ", " sendingAccounts}
        '';
        stdin = true;
        rules = [
          {
            match = [
              "*"
              "*"
              "*"
            ];
            lanes = interactive;
            taints = true;
            egress = true;
            outcome = {
              kind = "message";
              to = 1;
            };
          }
        ];
        credentials = lib.mergeAttrsList (lib.catAttrs "credentials" (lib.attrValues mailAccounts));
        skill = ./butler-skills/mail-send;
      };
    })

  ];
}
