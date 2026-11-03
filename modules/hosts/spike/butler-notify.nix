{ pkgs, ... }:
let
  spool = "/var/lib/butler-notify";
  group = "butler-notify";

  butler-notify = pkgs.writeShellApplication {
    name = "butler-notify";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.jq
    ];
    text = ''
      usage() {
        echo "usage: butler-notify [file...] <<'EOF' the message EOF  (sends Aaron a Discord DM from butler)" >&2
        exit 2
      }

      text=$(cat)
      [ -n "''${text//[[:space:]]/}" ] || [ "$#" -gt 0 ] || usage
      [ "$#" -le 10 ] || { echo "butler-notify: Discord takes at most 10 files" >&2; exit 2; }

      id="$(date +%Y%m%d-%H%M%S)-$$"
      names=()
      for file in "$@"; do
        [ -f "$file" ] || { echo "butler-notify: $file is not a file" >&2; exit 2; }
        name="$id-$(basename "$file")"
        [[ "$name" != *.json ]] || name="$name.txt"
        install -m 0640 "$file" "${spool}/$name"
        names+=("$name")
      done

      jq -n --arg text "$text" '{text: $text, files: $ARGS.positional}' --args "''${names[@]}" > "${spool}/$id.json.tmp"
      chmod 0640 "${spool}/$id.json.tmp"
      mv "${spool}/$id.json.tmp" "${spool}/$id.json"
      echo "Queued notice $id; butler sends it within 5 seconds."
    '';
  };

  # butler's own way to DM Aaron, from a scheduled job's thread above all, with no files, since those could be any it can read.
  notify = pkgs.writeShellApplication {
    name = "notify";
    text = ''
      [ $# -eq 0 ] || { echo "usage: notify <<'EOF' the message EOF  (DMs Aaron; takes no args)" >&2; exit 2; }
      exec ${butler-notify}/bin/butler-notify
    '';
  };

  # Says one short status line aloud in Aaron's live Discord call, or DMs it when no call is live, and prints which.
  butler-call-say = pkgs.writeShellApplication {
    name = "butler-call-say";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gnused
      pkgs.jq
    ];
    text = ''
      usage() {
        echo "usage: butler-call-say [--urgent] [--call-only] <<'EOF' one short line EOF  (says it in Aaron's live call, else DMs it, or with --call-only sends nothing)" >&2
        exit 2
      }

      urgent=false
      dm=true
      while [ "$#" -gt 0 ]; do
        case "$1" in
          --urgent) urgent=true ;;
          --call-only) dm=false ;;
          *) usage ;;
        esac
        shift
      done

      text=$(tr -s '[:space:]' ' ' | sed 's/^ //; s/ $//')
      [ -n "$text" ] || usage
      [ "''${#text}" -le 200 ] || { echo "butler-call-say: keep it to one short line of at most 200 characters" >&2; exit 2; }
      case "$text" in
        *http://* | *https://*) echo "butler-call-say: no links; say what happened in plain words" >&2; exit 2 ;;
      esac

      id="$(date +%Y%m%d-%H%M%S)-$$"
      jq -n --arg text "$text" --argjson urgent "$urgent" --argjson dm "$dm" '{text: (if $dm then $text else "" end), files: [], speak: {text: $text, urgent: $urgent, dm: $dm}}' > "${spool}/$id.json.tmp"
      chmod 0640 "${spool}/$id.json.tmp"
      mv "${spool}/$id.json.tmp" "${spool}/$id.json"

      receipt="${spool}/$id.result"
      for _ in $(seq 30); do
        if [ -s "$receipt" ]; then
          reason=$(jq -r '.reason' "$receipt")
          rm -f "$receipt"
          echo "''${reason^}."
          exit 0
        fi
        sleep 0.5
      done
      echo "Queued $id; butler had not picked it up after 15 seconds, so it will be said in his call or sent as a DM shortly."
    '';
  };

  # butler's own command: --urgent alone, since a session always wants the DM when no call is live.
  call-say = pkgs.writeShellApplication {
    name = "call-say";
    text = ''
      case "$*" in
        "" | --urgent) exec ${butler-call-say}/bin/butler-call-say "$@" ;;
        *) echo "usage: call-say [--urgent] <<'EOF' one short line EOF" >&2; exit 2 ;;
      esac
    '';
  };
in
{
  users.groups.${group} = { };
  users.users.butler.extraGroups = [ group ];
  users.users.aaron.extraGroups = [ group ];

  systemd.tmpfiles.rules = [ "d ${spool} 2770 root ${group} -" ];

  environment.systemPackages = [
    butler-notify
    butler-call-say
  ];

  butler.commands.notify = {
    package = notify;
    description = "Send Aaron a Discord DM, its text on stdin, such as a scheduled job's result. Takes no args.";
    stdin = true;
    rules = [
      {
        match = [ ];
        lanes = [
          "interactive"
          "cron"
        ];
      }
    ];
  };

  butler.commands.call-say = {
    package = call-say;
    description = "Give Aaron a shout: say one short plain line, on stdin, aloud in his live Discord call at the next gap, or DM it when no call is live; --urgent when something blocks on him.";
    stdin = true;
    rules = [
      {
        match = [ ];
        lanes = [
          "interactive"
          "cron"
        ];
      }
      {
        match = [ "--urgent" ];
        lanes = [
          "interactive"
          "cron"
        ];
      }
    ];
  };

  systemd.services.butler = {
    environment.DISCORD_NOTIFY_DIR = spool;
    serviceConfig.BindPaths = [ spool ];
  };
}
