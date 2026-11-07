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

  # Aaron's work calendar is read straight from Google, read-only, by butler-work-google.nix's reader.
  workGoogle = config.butler.workGoogle.enable;
  workReader = lib.getExe' config.butler.workGoogle.package "work-google";

  # Updates and deletes go through Home Assistant's websocket API, the only one that deletes events.
  calendar-edit = pkgs.writers.writePython3Bin "calendar-edit" {
    libraries = [ pkgs.python3Packages.websockets ];
    flakeIgnore = [ "E501" ];
  } (builtins.readFile ./butler-calendar/edit.py);

  calendar = pkgs.writeShellApplication {
    name = "calendar";

    runtimeInputs = [
      pkgs.coreutils
      pkgs.curl
      pkgs.jq
      pkgs.util-linux
      calendar-edit
    ];

    text = ''
      usage() {
        echo "usage: calendar calendars" >&2
        echo "       calendar agenda [days]" >&2
        echo "       calendar events <calendar.entity> <start> <end>" >&2
        echo "       calendar create <calendar.entity> <summary> <start> <end> [--named-by-aaron]  (description on stdin)" >&2
        echo "       calendar update <calendar.entity> <uid> [<recurrence_id>] [--summary S] [--start T] [--end T] [--location L] [--named-by-aaron]  (new description on stdin)" >&2
        echo "       calendar delete <calendar.entity> <uid> [<recurrence_id> [this|this-and-future] | series] [--named-by-aaron]" >&2
        ${lib.optionalString workGoogle ''echo "       calendar work agenda [days] | calendar work brief [days] | calendar work events <start> <end>  (read-only)" >&2''}
        echo "dates are YYYY-MM-DD, or YYYY-MM-DDTHH:MM[:SS] in local time unless an offset follows" >&2
        exit 2
      }

      home_assistant() {
        curl --silent --show-error --fail-with-body --globoff \
          --header @<(printf 'Authorization: Bearer %s\n' "$(< ${credential "home-assistant-token"})") \
          --header "Content-Type: application/json" \
          "$@"
      }

      # Every event created, from a conversation or a scheduled run, goes to audit/calendar in butler's memory.
      # It never fails the command, which has already created the event.
      audit() {
        local spool="$HOME/.local/state/calendar/audit-spool" thread title tag="" line
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
          setsid ${lib.getExe config.butler.memoryAudit} calendar "$spool" </dev/null >/dev/null 2>&1 &
        else
          echo "calendar: could not write the audit line" >&2
        fi
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
          | jq --arg calendar "$1" --from-file ${./butler-calendar/events.jq}
      }

      tabulate() {
        jq --slurp --raw-output --from-file ${./butler-calendar/tabulate.jq}
      }

      # update and delete print the event they changed in full and leave one audit line, which this spools.
      edit() {
        local log status=0
        log=$(mktemp)
        HOME_ASSISTANT_TOKEN_FILE=${credential "home-assistant-token"} CALENDAR_AUDIT_FILE=$log calendar-edit "$@" || status=$?
        while IFS= read -r line; do audit "$line"; done < "$log"
        rm -f "$log"
        return "$status"
      }

      [ $# -ge 1 ] || usage

      case "$1" in
        ${lib.optionalString workGoogle ''
          work)
            shift
            exec ${workReader} calendar "$@"
            ;;
        ''}
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
        update | delete)
          edit "$@"
          ;;
        create)
          named=()
          if [ $# -eq 6 ] && [ "$6" = "--named-by-aaron" ]; then
            named=(--named-by-aaron)
            set -- "''${@:1:5}"
          fi
          [ $# -eq 5 ] || usage
          entity "$2"
          HOME_ASSISTANT_TOKEN_FILE=${credential "home-assistant-token"} calendar-edit writable "$2" "''${named[@]}" || exit $?
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
          audit "created \"$3\" on $2 from $start to $end"
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

      # Aaron's own token reaches kranners; the backlogic organisation's repositories take their
      # own read-only fine-grained token, since one fine-grained token reaches one owner alone.
      token=${credential "github-issues-token"}
      backlogic_token=${credential "github-backlogic-token"}

      github() {
        curl --silent --show-error --fail-with-body --globoff \
          --header @<(printf 'Authorization: Bearer %s\n' "$(< "$token")") \
          --header "Accept: application/vnd.github+json" \
          --header "X-GitHub-Api-Version: 2022-11-28" \
          "$@"
      }

      [ $# -ge 1 ] || usage

      if [ "$1" != repos ]; then
        [ $# -ge 2 ] || usage
        [[ $2 =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ && $2 != *..* ]] || usage
        if [ "''${2%%/*}" = backlogic ]; then
          if [ "$1" = create ]; then
            echo "github-issue: backlogic's repositories are read-only here; file a backlogic ticket instead" >&2
            exit 77
          fi
          if [ ! -s "$backlogic_token" ]; then
            echo "github-issue: no token for the backlogic organisation yet; Aaron has to write a read-only fine-grained token to ${secret "github-backlogic-token"} on spike and restart butler" >&2
            exit 78
          fi
          token=$backlogic_token
        fi
      fi

      case "$1" in
        repos)
          github "https://api.github.com/user/repos?affiliation=owner&per_page=100" \
            | jq -r '.[] | select(.archived | not) | select(.has_issues) | "\(.full_name)\t\(.description // "")"'
          if [ -s "$backlogic_token" ]; then
            token=$backlogic_token
            github "https://api.github.com/user/repos?per_page=100" \
              | jq -r '.[] | select(.owner.login == "backlogic") | select(.archived | not) | "\(.full_name)\t\(.description // "") (read-only)"'
          fi
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

  # LoadCredential fails butler's start when its source is missing, so an empty placeholder
  # stands in until Aaron writes the backlogic organisation's token, and github-issue says it has none.
  config.systemd.services = lib.mkIf config.butler.credentialedTools {
    butler-github-backlogic-token = {
      description = "Create an empty placeholder for butler's backlogic GitHub token until one is written";
      unitConfig.ConditionPathExists = "!${secret "github-backlogic-token"}";
      serviceConfig = {
        Type = "oneshot";
        UMask = "0077";
      };
      script = ''
        touch ${secret "github-backlogic-token"}
      '';
    };
    butler = {
      requires = [ "butler-github-backlogic-token.service" ];
      after = [ "butler-github-backlogic-token.service" ];
    };
  };

  config.butler.commands = lib.mkIf config.butler.credentialedTools {
    calendar = {
      package = calendar;
      description = ''
        Read, add, change and delete events on Aaron's Google calendars through Home Assistant.
        calendar calendars | calendar agenda [days] | calendar events <calendar.entity> <start> <end> | calendar create <calendar.entity> <summary> <start> <end> [--named-by-aaron] (description on stdin)
        calendar update <calendar.entity> <uid> [<recurrence_id>] [--summary S] [--start T] [--end T] [--location L] [--named-by-aaron] (new description on stdin) | calendar delete <calendar.entity> <uid> [<recurrence_id> [this|this-and-future] | series] [--named-by-aaron]
        events and agenda print each event's uid and, for one occurrence of a recurring event, its recurrence_id; delete prints the deleted event in full so it can be made again, and a recurring event's whole series goes only with the word series.
        The work calendar is read-only, and the muted karate, Seido, Swinburne, school and timetable calendars are written only with --named-by-aaron, when Aaron named that calendar himself.
        Dates are YYYY-MM-DD, or YYYY-MM-DDTHH:MM in local time.
        Home Assistant's calendar.create_event cannot set reminders, so an event gets its calendar's default notifications; add any other reminder with the reminders tool.
        ${lib.optionalString workGoogle "calendar work agenda [days] | calendar work events <start> <end>: Aaron's work Google calendar, read-only, with each meeting's response, attendee count and Meet link; calendar work brief [days] gives only times and titles, the one view a scheduled run may read."}
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
          # A scheduled run may add events too, such as confirmation-sweep's for a booking it found in mail, each logged to audit/calendar.
          lanes = both;
          flags = [ "--named-by-aaron" ];
          acts = true;
          grant = "calendar";
        }
        {
          match = [
            "update"
            "**"
          ];
          # Changing or deleting an event is an ordinary calendar write under the same grant as adding one, as Aaron asked on 7 Nov 2026, each logged to audit/calendar with what it was.
          # As egress it asks once for the calendar grant in a thread that read private data, so text in mail or an invite cannot delete events unseen.
          lanes = interactive;
          egress = true;
          flags = [
            "--summary"
            "--start"
            "--end"
            "--location"
            "--named-by-aaron"
          ];
          acts = true;
          grant = "calendar";
        }
        {
          match = [
            "delete"
            "**"
          ];
          lanes = interactive;
          flags = [ "--named-by-aaron" ];
          egress = true;
          acts = true;
          grant = "calendar";
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
          grant = "home control";
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
        List Aaron's GitHub repositories and the backlogic organisation's, read their files and open issues, and open new issues on Aaron's own; backlogic's are read-only.
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
          grant = "issues and tickets";
        }
      ];
      credentials = {
        github-issues-token = secret "github-issues-token";
        github-backlogic-token = secret "github-backlogic-token";
      };
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
          grant = "issues and tickets";
        }
      ];
      credentials.backlogic-token = secret "backlogic-token";
      skill = ./butler-skills/backlogic;
    };
  };
}
