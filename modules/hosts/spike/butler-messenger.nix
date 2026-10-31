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
      text = matrix + text;
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

    jq --null-input --arg body "$body" '{msgtype: "m.text", body: $body}' \
      | matrix --request PUT --data @- "${client}/rooms/$path/send/m.room.message/butler-$(date +%s%N)" \
      | jq --raw-output '"Sent \(.event_id)"'
    echo "$now" >>"$sent"
  '';

  credentials.matrix-token = "/var/lib/secrets/butler-matrix-token";
in
{
  options.butler.messenger.enable = lib.mkEnableOption "the Messenger tools, once `messenger-setup` has written /var/lib/secrets/butler-matrix-token and logged the bridge in";

  config.butler.commands = lib.mkIf config.butler.messenger.enable {
    messenger-chats = {
      package = messenger-chats;
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
        }
      ];
      inherit credentials;
    };
  };
}
