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
          jq --null-input --arg entity "$2" --arg summary "$3" --arg span "$span" --arg start "$start" --arg end "$end" --rawfile description /dev/stdin \
            '{entity_id: $entity, summary: $summary, description: $description, "start_\($span)": $start, "end_\($span)": $end}' \
            | home_assistant --data @- "${homeAssistant}/api/services/calendar/create_event" >/dev/null
          echo "Created \"$3\" on $2 from $start to $end"
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
          jq --null-input --arg title "$3" --rawfile body /dev/stdin '{title: $title, body: $body}' \
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
          jq --null-input --arg project "$2" --arg title "$3" --rawfile text /dev/stdin \
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
      '';
      stdin = true;
      rules = [
        {
          match = [ "calendars" ];
          lanes = both;
        }
        {
          match = [
            "agenda"
            "**"
          ];
          lanes = both;
          taints = true;
        }
        {
          match = [
            "events"
            "**"
          ];
          lanes = both;
          taints = true;
        }
        {
          match = [
            "create"
            "**"
          ];
          lanes = interactive;
          egress = true;
        }
      ];
      credentials.home-assistant-token = secret "home-assistant-token";
      skill = ./butler-skills/google-calendar;
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
          taints = true;
        }
        {
          match = [
            "files"
            "**"
          ];
          lanes = interactive;
          taints = true;
        }
        {
          match = [
            "read"
            "**"
          ];
          lanes = interactive;
          taints = true;
        }
        {
          match = [
            "create"
            "**"
          ];
          lanes = interactive;
          egress = true;
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
          taints = true;
        }
        {
          match = [
            "file"
            "**"
          ];
          lanes = interactive;
        }
      ];
      credentials.backlogic-token = secret "backlogic-token";
      skill = ./butler-skills/backlogic;
    };
  };
}
