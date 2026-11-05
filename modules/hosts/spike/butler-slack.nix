{ pkgs, lib, ... }:
let
  token = "/var/lib/secrets/butler-slack-token";
  # The index's 6-hourly Slack read has its own token, which Aaron may reuse for live reads when its scopes cover them.
  indexToken = "/var/lib/secrets/butler-index-slack-token";
  scopes = [
    "channels:history"
    "channels:read"
    "groups:history"
    "groups:read"
    "im:history"
    "im:read"
    "mpim:history"
    "mpim:read"
    "search:read"
    "users:read"
  ];

  # `sudo butler-slack-login` takes Aaron's xoxp- user token hidden on stdin, or `--from-index` reuses the index's,
  # checks it with auth.test and its scopes, writes it mode 600 and asks butler for a restart at its next quiet moment.
  butler-slack-login = pkgs.writeShellApplication {
    name = "butler-slack-login";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.curl
      pkgs.jq
    ];
    text = ''
      if [ "$(id -u)" -ne 0 ]; then
        echo "run it as root: sudo butler-slack-login [--from-index]" >&2
        exit 1
      fi
      umask 077
      if [ "''${1:-}" = --from-index ]; then
        [ -s ${indexToken} ] || { echo "the index has no Slack token either; paste one instead" >&2; exit 1; }
        value=$(< ${indexToken})
      else
        read -r -s -p "Slack user token (xoxp-..., hidden): " value
        echo
      fi
      case "$value" in
        xoxp-*) ;;
        *) echo "that is not a Slack user token (xoxp-...); nothing changed" >&2; exit 1 ;;
      esac
      headers=$(mktemp)
      trap 'rm -f "$headers"' EXIT
      answer=$(curl --silent --show-error --dump-header "$headers" \
        --header @<(printf 'Authorization: Bearer %s\n' "$value") https://slack.com/api/auth.test)
      if [ "$(jq -r .ok <<<"$answer")" != true ]; then
        echo "Slack refused the token: $(jq -r '.error // "unknown error"' <<<"$answer"); nothing changed" >&2
        exit 1
      fi
      granted=$(tr -d '\r' < "$headers" | sed -n 's/^x-oauth-scopes: //Ip' | tr ',' '\n')
      missing=""
      for scope in ${lib.concatStringsSep " " scopes}; do
        grep -qx "$scope" <<<"$granted" || missing="$missing $scope"
      done
      if [ -n "$missing" ]; then
        echo "the token lacks:$missing; add them under User Token Scopes, reinstall the app and paste the new token; nothing changed" >&2
        exit 1
      fi
      printf '%s' "$value" > ${token}.new
      chmod 600 ${token}.new
      mv ${token}.new ${token}
      echo "Slack token for $(jq -r '.user + " in " + .team' <<<"$answer") written"
      install -d -m 755 /run/butler-restart
      if [ ! -f /run/butler-restart/wanted ]; then
        jq -n --argjson at "$(date +%s%3N)" '{at: $at, trigger: "slack-token", changes: ["Slack token for live reads written"]}' > /run/butler-restart/wanted.tmp
        chmod 644 /run/butler-restart/wanted.tmp
        mv /run/butler-restart/wanted.tmp /run/butler-restart/wanted
      fi
      echo "butler restarts to load it at its next quiet moment"
    '';
  };
  credential = "/run/credentials/butler.service/slack-token";

  both = [
    "interactive"
    "cron"
  ];

  slack = pkgs.writeShellApplication {
    name = "slack";

    runtimeInputs = [
      pkgs.coreutils
      pkgs.curl
      pkgs.jq
    ];

    text = ''
      usage() {
        echo "usage: slack channels" >&2
        echo "       slack history <channel> [count]" >&2
        echo "       slack dms" >&2
        echo "       slack search <query>..." >&2
        echo "       slack thread <channel> <ts>" >&2
        echo "       slack users" >&2
        echo "a channel is its id, such as C0123ABCD, or its name, such as general" >&2
        exit 2
      }

      if [ ! -s ${credential} ]; then
        echo "slack: no Slack token yet; Aaron has to run sudo butler-slack-login on spike, pasting his xoxp- user token, or sudo butler-slack-login --from-index to reuse the index's" >&2
        exit 78
      fi

      # Every call is a read: a GET of one of the conversations, users or search methods.
      api() {
        method=$1
        shift
        response=$(curl --silent --show-error --fail-with-body --globoff --get \
          --header @<(printf 'Authorization: Bearer %s\n' "$(< ${credential})") \
          "$@" "https://slack.com/api/$method")
        if [ "$(jq --raw-output .ok <<<"$response")" != true ]; then
          echo "slack: $method failed: $(jq --raw-output '.error // "unknown error"' <<<"$response")" >&2
          exit 1
        fi
        printf '%s\n' "$response"
      }

      # Follows a list method's cursor, printing each page's array named by $2, at most 20 pages.
      paged() {
        method=$1
        field=$2
        shift 2
        cursor=""
        for _ in $(seq 20); do
          page=$(api "$method" --data-urlencode "limit=200" --data-urlencode "cursor=$cursor" "$@")
          jq --compact-output --arg field "$field" '.[$field][]' <<<"$page"
          cursor=$(jq --raw-output '.response_metadata.next_cursor // ""' <<<"$page")
          [ -n "$cursor" ] || break
        done
      }

      users_json() {
        paged users.list members | jq --slurp 'map({key: .id, value: ((.profile.display_name | select(. != "")) // .real_name // .name)}) | from_entries'
      }

      conversations() {
        paged conversations.list channels --data-urlencode "types=$1" --data-urlencode "exclude_archived=true"
      }

      channel() {
        if [[ $1 =~ ^[CGD][A-Z0-9]{6,}$ ]]; then
          echo "$1"
          return
        fi
        name=''${1#\#}
        [[ $name =~ ^[a-z0-9._-]+$ ]] || usage
        id=$(conversations public_channel,private_channel | jq --raw-output --arg name "$name" 'select(.name == $name) | .id' | head -n 1)
        if [ -z "$id" ]; then
          echo "slack: no channel named $name that Aaron is in or can see" >&2
          exit 1
        fi
        echo "$id"
      }

      # Prints messages oldest first, mentions and links made readable.
      messages() {
        jq --raw-output --argjson users "$1" '
          def name: $users[.] // .;
          def readable: gsub("<@(?<id>[A-Z0-9]+)(\\|[^>]*)?>"; "@" + (.id | name))
            | gsub("<#[A-Z0-9]+\\|(?<name>[^>]*)>"; "#" + .name)
            | gsub("<!(?<what>[a-z]+)(\\|[^>]*)?>"; "@" + .what)
            | gsub("<(?<url>[^|>]+)\\|(?<label>[^>]*)>"; .label + " (" + .url + ")")
            | gsub("<(?<url>[^>]+)>"; .url)
            | gsub("&lt;"; "<") | gsub("&gt;"; ">") | gsub("&amp;"; "&");
          .messages | sort_by(.ts | tonumber) | .[]
          | "[\(.ts | tonumber | floor | strflocaltime("%Y-%m-%d %H:%M"))] ts=\(.ts) \(if .user then .user | name else .username // .bot_profile.name // "unknown" end)"
            + (if (.reply_count // 0) > 0 and .thread_ts == .ts then " (thread, \(.reply_count) replies)" else "" end)
            + ":\n" + ((.text // "") | readable)
            + (if .files then "\n[files: \(.files | map(.name // .title // "file") | join(", "))]" else "" end)
            + "\n"
        '
      }

      count() {
        [[ $1 =~ ^[0-9]{1,3}$ ]] && [ "$1" -ge 1 ] && [ "$1" -le 200 ] || usage
      }

      [ $# -ge 1 ] || usage

      case "$1" in
        channels)
          [ $# -eq 1 ] || usage
          conversations public_channel,private_channel \
            | jq --raw-output 'select(.is_member) | [.id, "#" + .name, (if .is_private then "private" else "public" end), (.num_members // 0 | tostring) + " members", (.topic.value // "")] | @tsv'
          ;;
        dms)
          [ $# -eq 1 ] || usage
          users=$(users_json)
          conversations im,mpim \
            | jq --raw-output --argjson users "$users" 'select(.is_user_deleted | not) | [.id, (if .is_im then "dm with " + ($users[.user] // .user) else "group dm " + (.purpose.value // .name) end)] | @tsv'
          ;;
        users)
          [ $# -eq 1 ] || usage
          paged users.list members \
            | jq --raw-output 'select((.deleted | not) and (.is_bot | not) and .id != "USLACKBOT") | [.id, .name, (.real_name // ""), (.profile.title // "")] | @tsv'
          ;;
        history)
          [ $# -ge 2 ] && [ $# -le 3 ] || usage
          limit=''${3:-20}
          count "$limit"
          id=$(channel "$2")
          users=$(users_json)
          api conversations.history --data-urlencode "channel=$id" --data-urlencode "limit=$limit" | messages "$users"
          ;;
        thread)
          [ $# -eq 3 ] || usage
          [[ $3 =~ ^[0-9]+\.[0-9]+$ ]] || usage
          id=$(channel "$2")
          users=$(users_json)
          api conversations.replies --data-urlencode "channel=$id" --data-urlencode "ts=$3" --data-urlencode "limit=200" | messages "$users"
          ;;
        search)
          [ $# -ge 2 ] || usage
          shift
          api search.messages --data-urlencode "query=$*" --data-urlencode "count=20" --data-urlencode "sort=timestamp" \
            | jq --raw-output '.messages.matches[]
                | "[\(.ts | tonumber | floor | strflocaltime("%Y-%m-%d %H:%M"))] \(if .channel.is_im then "dm" else "#" + (.channel.name // "?") end) channel=\(.channel.id) ts=\(.ts) \(.username // .user // "unknown"):\n\(.text // "")\n"'
          ;;
        *) usage ;;
      esac
    '';
  };
in
{
  environment.systemPackages = [ butler-slack-login ];

  # LoadCredential fails butler's start when its source is missing, so an empty placeholder
  # stands in until Aaron writes the token, and the command says it has none.
  systemd.services.butler-slack-token = {
    description = "Create an empty placeholder for butler's Slack token until one is written";
    unitConfig.ConditionPathExists = "!${token}";
    serviceConfig = {
      Type = "oneshot";
      UMask = "0077";
    };
    script = ''
      touch ${token}
    '';
  };

  systemd.services.butler = {
    requires = [ "butler-slack-token.service" ];
    after = [ "butler-slack-token.service" ];
  };

  butler.commands.slack = {
    private = true;
    package = slack;
    description = ''
      Read Aaron's work Slack workspace, read-only: it cannot post, react or edit.
      slack channels | slack history <channel> [count] | slack dms | slack search <query>... | slack thread <channel> <ts> | slack users
      A channel is its id, such as C0123ABCD or a DM's D0123ABCD, or a channel's name; count is 1 to 200, 20 unless given.
    '';
    rules = [
      {
        match = [ "channels" ];
        lanes = both;
      }
      {
        match = [ "dms" ];
        lanes = both;
      }
      {
        match = [ "users" ];
        lanes = both;
      }
      {
        match = [
          "history"
          "*"
        ];
        lanes = both;
      }
      {
        match = [
          "history"
          "*"
          "*"
        ];
        lanes = both;
      }
      {
        match = [
          "thread"
          "*"
          "*"
        ];
        lanes = both;
      }
      {
        match = [
          "search"
          "**"
        ];
        lanes = both;
      }
    ];
    credentials.slack-token = token;
    skill = ./butler-skills/slack;
  };
}
