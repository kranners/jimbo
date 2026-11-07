{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.services.matrix-tuwunel.settings.global) server_name port;

  token = "/run/credentials/butler.service/matrix-token";
  client = "http://127.0.0.1:${toString (lib.head port)}/_matrix/client/v3";

  sendsPerHour = 10;
  maxLength = 1000;
  maxShown = 1400;
  statusWaitSeconds = 15;

  both = [
    "interactive"
    "cron"
  ];

  matrix = ''
    matrix() {
      curl --silent --show-error --fail-with-body --globoff \
        --header @<(printf 'Authorization: Bearer %s\n' "$(< ${token})") \
        "$@"
    }

    chat_path() {
      [[ $1 =~ ^![A-Za-z0-9._~=-]+(:${server_name})?$ ]] || usage
      path=$(jq --raw-output --null-input --arg room "$1" '$room | @uri')
      if ! matrix "${client}/rooms/$path/state" \
        | jq --exit-status 'any(.[]; .type == "m.bridge") and all(.[]; .type != "m.room.create" or .content.type != "m.space")' >/dev/null; then
        echo "$1 is not a Messenger chat" >&2
        exit 2
      fi
      echo "$path"
    }
  '';

  # Every send goes to audit/messenger-send in butler's memory, with its thread, room and text; it never fails the send.
  audit = ''
    audit() {
      local spool="$HOME/.local/state/messenger-send/audit-spool" thread title tag="" line
      thread=''${BUTLER_THREAD_ID:-}
      thread=''${thread//[^0-9A-Za-z_-]/}
      thread=''${thread:0:32}
      if [ -n "$thread" ]; then
        title=''${BUTLER_THREAD_TITLE:-}
        title=''${title//[$'\t\n\r']/ }
        title=''${title//\"/\'}
        tag="[thread $thread''${title:+ \"''${title:0:60}\"}] "
      fi
      line="$(date +%F)"$'\t'"$(date '+%H:%M:%S %z') $tag''${1//[$'\t\n\r']/ }"
      if mkdir -p "''${spool%/*}" && ( flock 9 && printf '%s\n' "$line" >&9 ) 9>>"$spool"; then
        setsid ${lib.getExe config.butler.memoryAudit} messenger-send "$spool" </dev/null >/dev/null 2>&1 &
      else
        echo "messenger-send: could not write the audit line" >&2
      fi
    }
  '';

  wrapper =
    name: text:
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = [
        pkgs.coreutils
        pkgs.curl
        pkgs.gawk
        pkgs.jq
        pkgs.util-linux
      ];
      text = matrix + audit + text;
    };

  messenger-chats = wrapper "messenger-chats" ''
    usage() {
      echo "usage: messenger-chats [--marketplace]" >&2
      exit 2
    }

    marketplace=false
    case "$*" in
      "") ;;
      --marketplace) marketplace=true ;;
      *) usage ;;
    esac

    filter='{"room":{"state":{"types":["m.room.create","m.room.name","m.bridge","m.space.child"]},"timeline":{"limit":1},"ephemeral":{"not_types":["*"]},"account_data":{"not_types":["*"]}},"presence":{"not_types":["*"]},"account_data":{"not_types":["*"]}}'

    matrix --get --data-urlencode "filter=$filter" --data-urlencode timeout=0 "${client}/sync" \
      | jq --raw-output --argjson marketplace "$marketplace" '
          (.rooms.join // {})
          | to_entries
          | map({
              id: .key,
              state: ((.value.state.events // []) + (.value.timeline.events // [])),
              last: ((.value.timeline.events // []) | last | .origin_server_ts // 0),
              unread: (.value.unread_notifications.notification_count // 0)
            })
          | map(. + {
              space: any(.state[]; .type == "m.room.create" and .content.type == "m.space"),
              bridged: any(.state[]; .type == "m.bridge"),
              name: ([.state[] | select(.type == "m.room.name") | .content.name] | last // "(no name)")
            })
          | ([.[] | select(.space and .bridged) | .state[] | select(.type == "m.space.child" and ((.content.via // []) | length > 0)) | .state_key]) as $market
          | map(select(.bridged and (.space | not)) | . + {market: (.id | IN($market[]))})
          | map(select(.market or ($marketplace | not)))
          | sort_by(-.last)
          | .[:50][]
          | [.id, (.last / 1000 | floor | strflocaltime("%Y-%m-%d %H:%M")), "\(.unread) unread", (if .market then "marketplace: " else "" end) + .name]
          | @tsv'
  '';

  messenger-read = wrapper "messenger-read" ''
    usage() {
      echo "usage: messenger-read <room id> [count, at most 100]" >&2
      exit 2
    }

    [ $# -ge 1 ] && [ $# -le 2 ] || usage
    count=''${2:-20}
    [[ $count =~ ^[0-9]{1,3}$ ]] && [ "$count" -ge 1 ] && [ "$count" -le 100 ] || usage
    path=$(chat_path "$1")

    me=$(matrix "${client}/account/whoami" | jq --raw-output .user_id)
    filter='{"types":["m.room.message"],"lazy_load_members":true}'

    matrix --get --data-urlencode dir=b --data-urlencode "limit=$count" --data-urlencode "filter=$filter" "${client}/rooms/$path/messages" \
      | jq --raw-output --arg me "$me" '
          ([(.state // [])[] | select(.type == "m.room.member") | {key: .state_key, value: (.content.displayname // .state_key)}] | from_entries) as $names
          | .chunk
          | reverse
          | .[]
          | .content as $content
          | (if .sender == $me then "Aaron" else ($names[.sender] // .sender) end) as $sender
          | (if $content."m.relates_to".rel_type == "m.replace" then "(edited) \($content."m.new_content".body // "")"
             elif $content.body == null then "(deleted)"
             elif ($content.msgtype | IN("m.text", "m.notice", "m.emote")) then $content.body
             else "[\($content.msgtype | ltrimstr("m."))] \($content.body)"
             end) as $body
          | "\(.origin_server_ts / 1000 | floor | strflocaltime("%Y-%m-%d %H:%M")) \($sender): \($body | gsub("\n"; "\n    "))"'
  '';

  messenger-send = wrapper "messenger-send" ''
    usage() {
      echo "usage: messenger-send <room id>  (message on stdin, at most ${toString maxLength} characters)" >&2
      exit 2
    }

    fail() {
      echo "messenger-send: $1" >&2
      exit "''${2:-1}"
    }

    [ $# -eq 1 ] || usage

    body=$(head -c $((${toString maxLength} * 4 + 1)))
    [ -n "''${body//[[:space:]]/}" ] || fail "the message on stdin is empty" 2
    [[ ! ''${body//[$'\n\t']/} =~ [[:cntrl:]] ]] || fail "the message has control characters other than newline and tab" 2
    [ "''${#body}" -le ${toString maxLength} ] || fail "the message is over ${toString maxLength} characters; shorten it" 2
    shown=$(jq --null-input --arg body "$body" '$body | tojson | explode | map(if . > 65535 then 2 else 1 end) | add')
    [ "$shown" -le ${toString maxShown} ] || fail "the message is $shown characters as the approval shows it, over ${toString maxShown}; use fewer newlines, quotes, backslashes or emoji" 2
    [[ ! $body =~ ^[[:space:]]*! ]] || fail "a message may not start with !, which the bridge reads as a command" 2
    path=$(chat_path "$1")

    sent="$HOME/.local/state/messenger-sent"
    mkdir -p "$(dirname "$sent")"
    exec 9>>"$sent.lock"
    flock 9
    touch "$sent"
    now=$(date +%s)
    awk -v since=$((now - 3600)) '$1 > since' "$sent" >"$sent.new"
    mv "$sent.new" "$sent"
    if [ "$(wc -l <"$sent")" -ge ${toString sendsPerHour} ]; then
      fail "${toString sendsPerHour} messages were sent in the last hour, the most allowed; try again later" 75
    fi

    event=$(jq --null-input --arg body "$body" '{msgtype: "m.text", body: $body}' \
      | matrix --request PUT --data @- "${client}/rooms/$path/send/m.room.message/butler-$(date +%s%N)" \
      | jq --raw-output .event_id)
    echo "$now" >>"$sent"
    audit "send to $1: $body"

    # The homeserver taking the message is not Messenger delivering it: the bridge answers each message with a
    # com.beeper.message_send_status event, failing it when its Facebook login has lapsed, so wait for that.
    status=""
    for _ in $(seq ${toString statusWaitSeconds}); do
      status=$(matrix --get --data-urlencode dir=b --data-urlencode limit=30 \
          --data-urlencode 'filter={"types":["com.beeper.message_send_status"]}' "${client}/rooms/$path/messages" \
        | jq --compact-output --arg event "$event" \
          'first(.chunk[] | select(.content."m.relates_to".event_id == $event) | .content | {status, reason, message}) // empty') || status=""
      case $(jq --raw-output '.status // ""' <<<"$status") in
        SUCCESS) echo "Sent and delivered to Messenger ($event)"; exit 0 ;;
        FAIL_PERMANENT)
          audit "send to $1 failed: $(jq --raw-output '.message // .reason // "no reason"' <<<"$status")"
          fail "Messenger did not take it: $(jq --raw-output '[.reason, .message] | map(select(. != null)) | join(": ")' <<<"$status"); the bridge's Facebook login has probably lapsed, which Aaron fixes with sudo messenger-setup on spike" ;;
        FAIL_RETRIABLE)
          audit "send to $1 may have failed: $(jq --raw-output '.message // .reason // "no reason"' <<<"$status")"
          fail "the bridge had trouble sending it and may retry: $(jq --raw-output '[.reason, .message] | map(select(. != null)) | join(": ")' <<<"$status"); check with messenger-read before sending it again" ;;
      esac
      sleep 1
    done
    echo "Handed to the bridge ($event), but Messenger has not confirmed it after ${toString statusWaitSeconds} seconds; check with messenger-read before saying it went"
  '';

  credentials.matrix-token = "/var/lib/secrets/butler-matrix-token";
in
{
  options.butler.messenger.enable = lib.mkEnableOption "the Messenger tools, once `messenger-setup` has written /var/lib/secrets/butler-matrix-token and logged the bridge in";

  # LoadCredential fails butler's start when its source is missing, so an empty placeholder stands in until
  # `messenger-setup` writes the token, which it treats as missing, and the wrappers then fail with Matrix's 401.
  config.systemd.services = lib.mkIf config.butler.messenger.enable {
    butler-matrix-token = {
      description = "Create an empty placeholder for butler's Matrix token until messenger-setup writes one";
      unitConfig.ConditionPathExists = "!${credentials.matrix-token}";
      serviceConfig = {
        Type = "oneshot";
        UMask = "0077";
      };
      script = ''
        touch ${credentials.matrix-token}
      '';
    };
    butler = {
      requires = [ "butler-matrix-token.service" ];
      after = [ "butler-matrix-token.service" ];
    };
    butler-chat-sync = {
      requires = [ "butler-matrix-token.service" ];
      after = [ "butler-matrix-token.service" ];
    };
  };

  config.butler.commands = lib.mkIf config.butler.messenger.enable {
    messenger-chats = {
      package = messenger-chats;
      private = true;
      description = ''
        List Aaron's 50 most recent Messenger chats, Marketplace ones included, newest first: room id, time of its last activity, unread count, name.
        messenger-chats | messenger-chats --marketplace (Marketplace chats only)
      '';
      rules = [
        {
          match = [ ];
          lanes = both;
        }
        {
          match = [ "--marketplace" ];
          lanes = both;
        }
      ];
      inherit credentials;
      skill = ./butler-skills/messenger;
    };

    messenger-read = {
      package = messenger-read;
      private = true;
      description = ''
        Print the latest messages of one Messenger chat, oldest first, 20 unless a count up to 100 is given.
        messenger-read <room id> [count]
      '';
      rules = [
        {
          match = [ "*" ];
          lanes = both;
        }
        {
          match = [
            "*"
            "*"
          ];
          lanes = both;
        }
      ];
      inherit credentials;
    };

    messenger-send = {
      package = messenger-send;
      description = ''
        Send one Messenger message as Aaron, its text on stdin, to a chat from messenger-chats; Aaron approves every send.
        messenger-send <room id>
      '';
      stdin = true;
      rules = [
        {
          match = [ "*" ];
          lanes = [ "interactive" ];
          taints = true;
          egress = true;
          outcome = {
            kind = "message";
            to = 0;
          };
        }
      ];
      inherit credentials;
    };
  };
}
