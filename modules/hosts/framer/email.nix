{
  pkgs,
  lib,
  ...
}:
let
  accounts = {
    fastmail = {
      address = "aaron@cute.engineer";
      imapServer = "imap.fastmail.com:993";
      archiveMailbox = "Archive";
    };
    gmail = {
      address = "aaronpierce114@gmail.com";
      imapServer = "imap.gmail.com:993";
      archiveMailbox = "[Gmail]/All Mail";
    };
  };

  passwordFile = name: "/var/lib/secrets/email-${name}-password";

  himalayaConfig = (pkgs.formats.toml { }).generate "himalaya.toml" {
    accounts = lib.mapAttrs (name: account: {
      default = name == "fastmail";
      imap.server = account.imapServer;
      mailbox.alias.inbox = "INBOX";
      mailbox.alias.archive = account.archiveMailbox;
      imap.sasl.plain.username = account.address;
      imap.sasl.plain.password.command = "cat ${passwordFile name}";
    }) accounts;
  };

  mail = pkgs.writeShellApplication {
    name = "mail";

    runtimeInputs = [
      pkgs.himalaya
      pkgs.jq
    ];

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
        command himalaya --config ${himalayaConfig} --log-level off "$@"
      }

      [ $# -ge 1 ] || usage

      if [ "$1" = accounts ]; then
        himalaya account list
        exit
      fi

      if [ "$1" = unread-counts ]; then
        for account in ${lib.escapeShellArgs (lib.attrNames accounts)}; do
          echo "$account $(himalaya --json --account "$account" envelope search --page-size 1000 not flag seen | jq '.envelopes | length')" &
        done
        wait
        exit
      fi

      [ $# -ge 2 ] || usage
      account="$1"
      action="$2"
      shift 2

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
in
{
  environment.systemPackages = [ mail ];

  openclaw.skills.email = ./skills/email;
  openclaw.commands = [ mail ];
}
