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

  homeAssistant = "http://127.0.0.1:8123";

  calendar = pkgs.writeShellApplication {
    name = "calendar";

    runtimeInputs = [
      pkgs.coreutils
      pkgs.curl
      pkgs.jq
    ];

    text = ''
      usage() {
        echo "usage: calendar calendars" >&2
        echo "       calendar agenda [days]" >&2
        echo "       calendar events <calendar.entity> <start> <end>" >&2
        echo "       calendar create <calendar.entity> <summary> <start> <end>  (description on stdin)" >&2
        echo "dates are YYYY-MM-DD, or YYYY-MM-DDTHH:MM[:SS] in local time unless an offset follows" >&2
        exit 2
      }

      home_assistant() {
        curl --silent --show-error --fail-with-body --globoff \
          --header @<(printf 'Authorization: Bearer %s\n' "$(< ${credential "home-assistant-token"})") \
          --header "Content-Type: application/json" \
          "$@"
      }

      entity() {
        [[ $1 =~ ^calendar\.[a-z0-9_]+$ ]] || usage
      }

      day() {
        [[ $1 =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]
      }

      instant() {
        [[ $1 =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}(T[0-9]{2}:[0-9]{2}(:[0-9]{2})?([+-][0-9]{2}:[0-9]{2}|Z)?)?$ ]] || usage
        date --date "$1" +%FT%T%:z 2>/dev/null || usage
      }

      events() {
        home_assistant --get --data-urlencode "start=$2" --data-urlencode "end=$3" "${homeAssistant}/api/calendars/$1" \
          | jq --arg calendar "$1" '.[] | {calendar: $calendar, start: (.start.dateTime // .start.date), end: (.end.dateTime // .end.date), summary, location}'
      }

      tabulate() {
        jq --slurp --raw-output 'sort_by(.start) | .[] | [.start, .end, .calendar, .summary, (.location // "")] | @tsv'
      }

      [ $# -ge 1 ] || usage

      case "$1" in
        calendars)
          [ $# -eq 1 ] || usage
          home_assistant "${homeAssistant}/api/calendars" | jq --raw-output '.[] | "\(.entity_id)\t\(.name)"'
          ;;
        agenda)
          [ $# -le 2 ] || usage
          days=''${2:-1}
          [[ $days =~ ^[0-9]{1,2}$ ]] && [ "$days" -ge 1 ] || usage
          start=$(date --date "$(date +%F)" +%FT%T%:z)
          end=$(date --date "$(date +%F) $days day" +%FT%T%:z)
          home_assistant "${homeAssistant}/api/calendars" \
            | jq --raw-output '.[].entity_id' \
            | while read -r calendar; do events "$calendar" "$start" "$end"; done \
            | tabulate
          ;;
        events)
          [ $# -eq 4 ] || usage
          entity "$2"
          start=$(instant "$3")
          end=$(instant "$4")
          events "$2" "$start" "$end" | tabulate
          ;;
        create)
          [ $# -eq 5 ] || usage
          entity "$2"
          if day "$4" && day "$5"; then
            instant "$4" >/dev/null
            instant "$5" >/dev/null
            start=$4
            end=$5
            span="date"
          else
            start=$(instant "$4")
            end=$(instant "$5")
            span="date_time"
          fi
          # Node hands a child its stdin as a socket, which /dev/stdin cannot open, so read fd 0 itself.
          description=$(cat 2>/dev/null) || description=""
          jq --null-input --arg entity "$2" --arg summary "$3" --arg span "$span" --arg start "$start" --arg end "$end" --arg description "$description" \
            '{entity_id: $entity, summary: $summary, description: $description, "start_\($span)": $start, "end_\($span)": $end}' \
            | home_assistant --data @- "${homeAssistant}/api/services/calendar/create_event" >/dev/null
          echo "Created \"$3\" on $2 from $start to $end"
          ;;
        *) usage ;;
      esac
    '';
  };

  # Zones are edited only through Home Assistant's websocket API.
  home-zone = pkgs.writers.writePython3Bin "home-zone" {
    libraries = [ pkgs.python3Packages.websockets ];
    flakeIgnore = [ "E501" ];
  } (builtins.readFile ./butler-home/zone.py);

  # Device control through the same Home Assistant token as the calendar.
  # Only the domains and services below may be called, and locks, alarm panels,
  # garage doors and gates can be read but never called.
  home = pkgs.writeShellApplication {
    name = "home";

    runtimeInputs = [
      pkgs.coreutils
      pkgs.curl
      pkgs.jq
      home-zone
    ];

    text = ''
      usage() {
        echo "usage: home areas" >&2
        echo "       home area <area_id>" >&2
        echo "       home list [text]" >&2
        echo "       home state <entity_id>" >&2
        echo "       home call <domain.service> <entity_id> [key=value...]" >&2
        echo "       home zone list | create <name> <lat> <lng> <radius_m> [icon] | update <name> <lat> <lng> <radius_m> [icon] | rename <name> <new name> | delete <name>" >&2
        exit 2
      }

      refuse() {
        echo "home: $*" >&2
        exit 77
      }

      home_assistant() {
        curl --silent --show-error --fail-with-body --globoff \
          --header @<(printf 'Authorization: Bearer %s\n' "$(< ${credential "home-assistant-token"})") \
          --header "Content-Type: application/json" \
          "$@"
      }

      template() {
        jq --null-input --arg template "$1" '{template: $template}' \
          | home_assistant --data @- "${homeAssistant}/api/template" \
          || refuse "Home Assistant refused to render a template, which needs the token's user to be an administrator"
      }

      entity() {
        [[ $1 =~ ^[a-z_]+\.[a-z0-9_]+$ ]] || usage
      }

      summarise() {
        jq --raw-output '.[] | [.entity_id, .state, (.attributes.friendly_name // "")] | @tsv'
      }

      declare -A services=(
        [light]="turn_on turn_off toggle"
        [switch]="turn_on turn_off toggle"
        [input_boolean]="turn_on turn_off toggle"
        [fan]="turn_on turn_off toggle set_percentage oscillate set_direction set_preset_mode"
        [cover]="open_cover close_cover stop_cover toggle set_cover_position open_cover_tilt close_cover_tilt stop_cover_tilt set_cover_tilt_position"
        [valve]="open_valve close_valve stop_valve toggle set_valve_position"
        [vacuum]="start pause stop return_to_base locate clean_spot set_fan_speed"
        [climate]="turn_on turn_off set_temperature set_hvac_mode set_fan_mode set_preset_mode set_humidity"
        [humidifier]="turn_on turn_off toggle set_humidity set_mode"
        [media_player]="turn_on turn_off media_play media_pause media_stop volume_set volume_mute media_next_track media_previous_track"
      )

      [ $# -ge 1 ] || usage

      case "$1" in
        areas)
          [ $# -eq 1 ] || usage
          template '[{% for a in areas() %}{{ {"area": a, "name": area_name(a), "entities": area_entities(a) | count} | tojson }}{{ "," if not loop.last }}{% endfor %}]' \
            | jq --raw-output '.[] | "\(.area)\t\(.name)\t\(.entities) entities"'
          ;;
        area)
          [ $# -eq 2 ] || usage
          [[ $2 =~ ^[a-z0-9_]+$ ]] || usage
          ids=$(template "{{ area_entities('$2') | tojson }}")
          home_assistant "${homeAssistant}/api/states" \
            | jq --argjson ids "$ids" '[.[] | select(.entity_id | IN($ids[]))]' \
            | summarise
          ;;
        list)
          [ $# -le 2 ] || usage
          home_assistant "${homeAssistant}/api/states" \
            | jq --arg text "''${2:-}" '[.[] | select(($text | ascii_downcase) as $t | (.entity_id | ascii_downcase | contains($t)) or ((.attributes.friendly_name // "") | ascii_downcase | contains($t)))] | sort_by(.entity_id)' \
            | summarise
          ;;
        state)
          [ $# -eq 2 ] || usage
          entity "$2"
          home_assistant "${homeAssistant}/api/states/$2" \
            | jq '{entity_id, state, attributes: (.attributes | del(.entity_picture)), last_changed}'
          ;;
        call)
          [ $# -ge 3 ] || usage
          [[ $2 =~ ^([a-z_]+)\.([a-z_]+)$ ]] || usage
          domain=''${BASH_REMATCH[1]}
          service=''${BASH_REMATCH[2]}
          entity "$3"
          [ "''${3%%.*}" = "$domain" ] || refuse "$3 is not a $domain entity"
          allowed=''${services[$domain]:-}
          [ -n "$allowed" ] || refuse "$domain cannot be controlled, only read; locks, alarm panels, scripts, scenes and the rest stay with Aaron"
          [[ " $allowed " == *" $service "* ]] || refuse "$domain.$service is not allowed; allowed: $allowed"
          current=$(home_assistant "${homeAssistant}/api/states/$3")
          if [ "$domain" = cover ]; then
            class=$(jq --raw-output '.attributes.device_class // ""' <<<"$current")
            case "$class" in
              garage | gate | door) refuse "$3 is a $class, which can only be read" ;;
            esac
          fi
          shift 3
          for pair in "$@"; do
            [[ $pair =~ ^[a-z_]+=.+$ ]] || usage
            case "''${pair%%=*}" in
              entity_id | area_id | device_id | floor_id | label_id) usage ;;
            esac
          done
          target=$(jq --raw-output '.entity_id' <<<"$current")
          jq --null-input --arg entity "$target" '$ARGS.positional
              | map(index("=") as $i | {key: .[:$i], value: (.[$i + 1:] | . as $v | try fromjson catch $v)})
              | from_entries + {entity_id: $entity}' --args "$@" \
            | home_assistant --data @- "${homeAssistant}/api/services/$domain/$service" >/dev/null
          echo "Called $domain.$service on $target"
          sleep 1
          home_assistant "${homeAssistant}/api/states/$target" | jq --slurp '.' | summarise
          ;;
        zone)
          shift
          HOME_ASSISTANT_TOKEN_FILE=${credential "home-assistant-token"} exec home-zone "$@"
          ;;
        *) usage ;;
      esac
    '';
  };

  github-issue = pkgs.writeShellApplication {
    name = "github-issue";

    runtimeInputs = [
      pkgs.curl
      pkgs.jq
    ];

    text = ''
      usage() {
        echo "usage: github-issue repos" >&2
        echo "       github-issue files <owner/repo> [path regex]" >&2
        echo "       github-issue read <owner/repo> <path>" >&2
        echo "       github-issue issues <owner/repo>" >&2
        echo "       github-issue create <owner/repo> <title>  (body on stdin)" >&2
        exit 2
      }

      github() {
        curl --silent --show-error --fail-with-body --globoff \
          --header @<(printf 'Authorization: Bearer %s\n' "$(< ${credential "github-issues-token"})") \
          --header "Accept: application/vnd.github+json" \
          --header "X-GitHub-Api-Version: 2022-11-28" \
          "$@"
      }

      [ $# -ge 1 ] || usage

      if [ "$1" != repos ]; then
        [ $# -ge 2 ] || usage
        [[ $2 =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ && $2 != *..* ]] || usage
      fi

      case "$1" in
        repos)
          github "https://api.github.com/user/repos?affiliation=owner&per_page=100" \
            | jq -r '.[] | select(.archived | not) | select(.has_issues) | "\(.full_name)\t\(.description // "")"'
          ;;
        files)
          [ $# -ge 2 ] || usage
          github "https://api.github.com/repos/$2/git/trees/HEAD?recursive=1" \
            | jq -r --arg pattern "''${3:-.}" '.tree[] | select(.type == "blob") | .path | select(test($pattern; "i"))'
          ;;
        read)
          [ $# -eq 3 ] || usage
          [[ $3 != /* && $3 != *..* && $3 != *[?#]* ]] || usage
          github "https://api.github.com/repos/$2/contents/$3" | jq -r '.content | gsub("\\n"; "") | @base64d'
          ;;
        issues)
          [ $# -eq 2 ] || usage
          github "https://api.github.com/repos/$2/issues?state=open&per_page=100" \
            | jq -r '.[] | select(.pull_request | not) | "#\(.number)\t\(.title)"'
          ;;
        create)
          [ $# -eq 3 ] || usage
          body=$(cat 2>/dev/null) || body=""
          jq --null-input --arg title "$3" --arg body "$body" '{title: $title, body: $body}' \
            | github --data @- "https://api.github.com/repos/$2/issues" \
            | jq -r '"#\(.number) \(.html_url)"'
          ;;
        *) usage ;;
      esac
    '';
  };

  backlogic = "http://127.0.0.1:4200";

  backlogic-ticket = pkgs.writeShellApplication {
    name = "backlogic-ticket";

    runtimeInputs = [
      pkgs.curl
      pkgs.jq
    ];

    text = ''
      usage() {
        echo "usage: backlogic-ticket projects" >&2
        echo "       backlogic-ticket tickets <project>" >&2
        echo "       backlogic-ticket file <project> <title>  (text on stdin)" >&2
        exit 2
      }

      backlogic() {
        curl --silent --show-error --fail-with-body --globoff \
          --header @<(printf 'Authorization: Bearer %s\n' "$(< ${credential "backlogic-token"})") \
          --header "Content-Type: application/json" \
          "$@"
      }

      [ $# -ge 1 ] || usage

      case "$1" in
        projects)
          backlogic "${backlogic}/api/snapshot" \
            | jq -r '.tickets | group_by(.project) | .[] | "\(.[0].project)\t\(map(select(.doneAt == null)) | length) open"'
          ;;
        tickets)
          [ $# -eq 2 ] || usage
          backlogic "${backlogic}/api/snapshot" \
            | jq -r --arg project "$2" '.tickets[] | select(.project == $project and .doneAt == null) | "\(.id)\t\(.title)"'
          ;;
        file)
          [ $# -eq 3 ] || usage
          text=$(cat 2>/dev/null) || text=""
          jq --null-input --arg project "$2" --arg title "$3" --arg text "$text" \
            '{project: $project, title: $title, text: $text, assignee: "owner"}' \
            | backlogic --data @- "${backlogic}/api/tickets" \
            | jq -r '.id'
          ;;
        *) usage ;;
      esac
    '';
  };
in
{
  options.butler.credentialedTools = lib.mkEnableOption "the Fastmail and Gmail accounts and the calendar, GitHub and backlogic tools, once their credentials are in /var/lib/secrets";

  config.butler.commands = lib.mkIf config.butler.credentialedTools {
    calendar = {
      package = calendar;
      description = ''
        Read and add events on Aaron's Google calendars through Home Assistant.
        calendar calendars | calendar agenda [days] | calendar events <calendar.entity> <start> <end> | calendar create <calendar.entity> <summary> <start> <end> (description on stdin)
        Dates are YYYY-MM-DD, or YYYY-MM-DDTHH:MM in local time.
        Home Assistant's calendar.create_event cannot set reminders, so an event gets its calendar's default notifications; add any other reminder with the reminders tool.
      '';
      stdin = true;
      rules = [
        {
          match = [ "calendars" ];
          lanes = both ++ [ "call" ];
        }
        {
          match = [
            "agenda"
            "**"
          ];
          lanes = both ++ [ "call" ];
        }
        {
          match = [
            "events"
            "**"
          ];
          lanes = both ++ [ "call" ];
        }
        {
          match = [
            "create"
            "**"
          ];
          lanes = interactive;
          acts = true;
        }
      ];
      credentials.home-assistant-token = secret "home-assistant-token";
      skill = ./butler-skills/google-calendar;
    };

    home = {
      package = home;
      description = ''
        Read and control the devices in Aaron's home through Home Assistant: lights, blinds, irrigation valves, climate, fans, the vacuum and media players.
        home areas | home area <area_id> | home list [text] | home state <entity_id> | home call <domain.service> <entity_id> [key=value...]
        home zone list | home zone create <name> <lat> <lng> <radius_m> [icon] | home zone update <name> <lat> <lng> <radius_m> [icon] | home zone rename <name> <new name> | home zone delete <name>
        Zones are the places Home Assistant tracks people at; the Home zone itself is read-only.
        Locks, alarm panels, garage doors, gates, scripts and scenes can be read but never called.
      '';
      rules = [
        {
          match = [ "areas" ];
          lanes = both ++ [ "call" ];
        }
        {
          match = [
            "area"
            "**"
          ];
          lanes = both ++ [ "call" ];
        }
        {
          match = [
            "list"
            "**"
          ];
          lanes = both ++ [ "call" ];
        }
        {
          match = [
            "state"
            "**"
          ];
          lanes = both ++ [ "call" ];
        }
        {
          match = [
            "call"
            "**"
          ];
          lanes = both;
          acts = true;
        }
        {
          match = [
            "zone"
            "list"
          ];
          lanes = both ++ [ "call" ];
        }
        {
          match = [
            "zone"
            "**"
          ];
          lanes = both;
          acts = true;
        }
      ];
      credentials.home-assistant-token = secret "home-assistant-token";
      skill = ./butler-skills/home;
    };

    github-issue = {
      package = github-issue;
      description = ''
        List Aaron's GitHub repositories, read their files and open issues, and open new issues.
        github-issue repos | github-issue files <owner/repo> [path regex] | github-issue read <owner/repo> <path> | github-issue issues <owner/repo> | github-issue create <owner/repo> <title> (body on stdin)
      '';
      stdin = true;
      rules = [
        {
          match = [ "repos" ];
          lanes = both;
        }
        {
          match = [
            "issues"
            "**"
          ];
          lanes = both;
        }
        {
          match = [
            "files"
            "**"
          ];
          lanes = interactive;
        }
        {
          match = [
            "read"
            "**"
          ];
          lanes = interactive;
        }
        {
          match = [
            "create"
            "**"
          ];
          lanes = interactive;
          acts = true;
        }
      ];
      credentials.github-issues-token = secret "github-issues-token";
      skill = ./butler-skills/github-issues;
    };

    backlogic-ticket = {
      package = backlogic-ticket;
      description = ''
        List backlogic's projects and their open tickets, and file new tickets.
        backlogic-ticket projects | backlogic-ticket tickets <project> | backlogic-ticket file <project> <title> (text on stdin)
      '';
      stdin = true;
      rules = [
        {
          match = [ "projects" ];
          lanes = both;
        }
        {
          match = [
            "tickets"
            "**"
          ];
          lanes = both;
        }
        {
          match = [
            "file"
            "**"
          ];
          lanes = interactive;
          acts = true;
        }
      ];
      credentials.backlogic-token = secret "backlogic-token";
      skill = ./butler-skills/backlogic;
    };
  };
}
