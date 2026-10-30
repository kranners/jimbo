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

  mailPassword = name: "email-${name}-password";

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
        echo "       mail <account> unread [count]" >&2
        echo "       mail <account> list [count]" >&2
        echo "       mail <account> search <query>..." >&2
        echo "       mail <account> read <id>" >&2
        echo "       mail <account> archive <id>..." >&2
        exit 2
      }

      himalaya() {
        ${himalaya} "$@"
      }

      [ $# -ge 1 ] || usage

      if [ "$1" = accounts ]; then
        himalaya account list
        exit
      fi

      if [ "$1" = unread-counts ]; then
        for account in ${lib.escapeShellArgs (lib.attrNames mailAccounts)}; do
          if count=$(himalaya --json --account "$account" envelope search --page-size 1000 not flag seen | jq '.envelopes | length'); then
            echo "$account $count"
          else
            echo "$account unavailable"
          fi
        done
        exit
      fi

      [ $# -ge 2 ] || usage
      account="$1"
      action="$2"
      shift 2

      for argument in "$account" "$@"; do
        case "$argument" in
          -*) usage ;;
        esac
      done

      case "$action" in
        mailboxes) himalaya --account "$account" mailbox list ;;
        unread) himalaya --account "$account" envelope search --page-size "''${1:-10}" not flag seen order by date desc ;;
        list) himalaya --account "$account" envelope list --page-size "''${1:-10}" ;;
        search) himalaya --account "$account" envelope search "$@" ;;
        read) [ $# -eq 1 ] || usage; himalaya --account "$account" message read "$1" ;;
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
        description = ''
            Read and archive Aaron's email; it cannot delete or move mail anywhere else, and sends only through mail-send.
          mail accounts | mail unread-counts | mail <account> mailboxes | mail <account> unread [count] | mail <account> list [count] | mail <account> search <query>... | mail <account> read <id> | mail <account> archive <id>...
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
          map
            (action: {
              match = [
                "*"
                action
                "**"
              ];
              lanes = both;
              taints = true;
            })
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
          }
        ];
        credentials = lib.mergeAttrsList (lib.catAttrs "credentials" (lib.attrValues mailAccounts));
        skill = ./butler-skills/mail-send;
      };
    })

  ];
}
