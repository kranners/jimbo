{
  config,
  pkgs,
  lib,
  ...
}:
let
  inherit (config.users.users.butler) home;

  both = [
    "interactive"
    "cron"
  ];
  interactive = [ "interactive" ];

  verbs =
    lanes: taints:
    map (verb: {
      match = verb ++ [ "**" ];
      inherit lanes taints;
    });

  garmin = pkgs.writeShellApplication {
    name = "garmin";

    runtimeInputs = [
      pkgs.coreutils
      pkgs.curl
      pkgs.jq
    ];

    text = ''
      usage() {
        echo "usage: garmin summary [day]" >&2
        echo "       garmin sleep [day]" >&2
        echo "       garmin sleep-range [from [to]]" >&2
        echo "       garmin hrv [day]" >&2
        echo "       garmin hrv-range [from [to]]" >&2
        echo "       garmin body-battery [from [to]]" >&2
        echo "       garmin stress [from [to]]" >&2
        echo "       garmin steps [from [to]]" >&2
        echo "       garmin activities [count]" >&2
        echo "       garmin activity <id>" >&2
        echo "       garmin profile" >&2
        echo "a day is YYYY-MM-DD, today or yesterday; a range defaults to the last 7 days" >&2
        exit 2
      }

      api=https://personal.connectapi.garmin.com
      key=/run/credentials/butler.service/garmin-api-key
      cache=${home}/.cache/garmin
      token=$cache/token
      body=$(mktemp)
      trap 'rm -f "$body"' EXIT

      expiry() {
        local payload
        payload=$(cut -d . -f 2 | tr '_-' '/+')
        while (( ''${#payload} % 4 )); do payload+="="; done
        base64 --decode <<<"$payload" 2>/dev/null | jq --raw-output '.exp // 0 | floor' 2>/dev/null || echo 0
      }

      mint() {
        if [ ! -r "$key" ]; then
          echo "garmin: there is no Personal API key at $key" >&2
          exit 75
        fi
        install -d -m 700 "$cache"
        status=$(curl --silent --show-error --output "$body" --write-out '%{http_code}' --request POST \
          --header @<(printf 'Authorization: ApiKey %s\n' "$(< "$key")") \
          --header 'Accept: */*' \
          "$api/personalapitoken-service/personal-api/personal-api-key/token")
        if [[ $status != 2* ]]; then
          echo "garmin: Garmin refused the Personal API key (HTTP $status); Aaron may need to make a new one at connect.garmin.com" >&2
          exit 75
        fi
        fresh=$(mktemp "$cache/token.XXXXXX")
        tr -d '[:space:]' <"$body" >"$fresh"
        mv "$fresh" "$token"
      }

      bearer() {
        local expires=0
        [ ! -s "$token" ] || expires=$(expiry <"$token")
        (( expires - $(date +%s) > 3600 )) || mint
        cat "$token"
      }

      get() {
        local path=$1 access
        shift
        for attempt in 1 2; do
          access=$(bearer)
          status=$(curl --silent --show-error --globoff --get --output "$body" --write-out '%{http_code}' \
            --header @<(printf 'Authorization: Bearer %s\n' "$access") \
            --header 'Accept: application/json' \
            "$@" "$api$path")
          if [ "$status" = 401 ] && [ "$attempt" = 1 ]; then
            rm -f "$token"
            continue
          fi
          break
        done
        if [[ $status != 2* ]]; then
          echo "garmin: GET $path returned HTTP $status" >&2
          exit 1
        fi
        [ ! -s "$body" ] || jq --compact-output --from-file ${./butler-health/garmin-clean.jq} "$body"
      }

      day() {
        case $1 in
          today | yesterday) date --date "$1" +%F ;;
          *)
            [[ $1 =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || usage
            date --date "$1" +%F 2>/dev/null || usage
            ;;
        esac
      }

      [ $# -ge 1 ] || usage
      verb=$1
      shift

      case $verb in
        summary | sleep | hrv)
          [ $# -le 1 ] || usage
          on=$(day "''${1:-today}")
          ;;
        sleep-range | hrv-range | body-battery | stress | steps)
          [ $# -le 2 ] || usage
          from=$(day "''${1:-$(date --date '6 days ago' +%F)}")
          to=$(day "''${2:-today}")
          [[ ! $from > $to ]] || usage
          ;;
      esac

      case $verb in
        summary) get /usersummary-service/v2/dailysummaries --data-urlencode "startDate=$on" --data-urlencode "endDate=$on" ;;
        sleep) get /sleep-service/sleep/dailySleep --data-urlencode "date=$on" ;;
        sleep-range) get /sleep-service/sleep/dailySleepSummariesByDate --data-urlencode "startDate=$from" --data-urlencode "endDate=$to" ;;
        hrv) get "/hrv-service/hrv/$on" ;;
        hrv-range) get "/hrv-service/hrv/daily/$from/$to" ;;
        body-battery) get /wellness-service/wellness/bodyBattery/reports/daily --data-urlencode "startDate=$from" --data-urlencode "endDate=$to" ;;
        stress) get "/usersummary-service/stats/stress/daily/$from/$to" ;;
        steps) get "/usersummary-service/stats/steps/daily/$from/$to" ;;
        activities)
          [ $# -le 1 ] || usage
          count=''${1:-10}
          [[ $count =~ ^[0-9]{1,2}$ ]] && [ "$count" -ge 1 ] && [ "$count" -le 50 ] || usage
          get /activitylist-service/activities/search/activities --data-urlencode start=0 --data-urlencode "limit=$count"
          ;;
        activity)
          [ $# -eq 1 ] && [[ $1 =~ ^[0-9]{1,20}$ ]] || usage
          get "/activity-service/activity/$1"
          ;;
        profile)
          [ $# -eq 0 ] || usage
          get /userprofile-service/userprofile/settings
          ;;
        *) usage ;;
      esac
    '';
  };

  hevy = pkgs.writers.writePython3Bin "hevy" {
    libraries = [ pkgs.python3Packages.requests ];
    flakeIgnore = [ "E501" ];
  } (builtins.readFile ./butler-health/hevy.py);
in
{
  options.butler = {
    garmin.enable = lib.mkEnableOption "the garmin command, once a Garmin Connect Personal API key is in /var/lib/secrets/butler-garmin-api-key";
    hevy.enable = lib.mkEnableOption "the hevy command, once `sudo -u butler hevy login` has stored a Hevy web session";
  };

  config = lib.mkMerge [
    (lib.mkIf config.butler.garmin.enable {
      butler.commands.garmin = {
        package = garmin;
        description = ''
          Read Aaron's Garmin health data: sleep, HRV, Body Battery, stress, steps, resting heart rate and activities. Prints JSON of numbers, dates and enum codes only.
          garmin summary [day] | garmin sleep [day] | garmin sleep-range [from [to]] | garmin hrv [day] | garmin hrv-range [from [to]] | garmin body-battery [from [to]] | garmin stress [from [to]] | garmin steps [from [to]] | garmin activities [count] | garmin activity <id> | garmin profile
          A day is YYYY-MM-DD, today or yesterday; a range defaults to the last 7 days.
        '';
        rules = verbs both false (
          map lib.singleton [
            "summary"
            "sleep"
            "sleep-range"
            "hrv"
            "hrv-range"
            "body-battery"
            "stress"
            "steps"
            "activities"
            "activity"
            "profile"
          ]
        );
        credentials.garmin-api-key = "/var/lib/secrets/butler-garmin-api-key";
        skill = ./butler-skills/garmin;
      };
    })

    (lib.mkIf config.butler.hevy.enable {
      environment.systemPackages = [ hevy ];

      butler.commands.hevy = {
        package = hevy;
        description = ''
          Read Aaron's Hevy workouts, exercise history, templates and routines, and change only the routines in its own "Butler plan" folder, through drafts Aaron approves.
          hevy workouts [since YYYY-MM-DD] | hevy workout <id> | hevy history <template id> [since YYYY-MM-DD] | hevy templates [search words] | hevy routines | hevy routine <id> | hevy folders | hevy routine draft <A|B> (draft JSON on stdin) | hevy routine diff <A|B> <sha256> | hevy routine apply <A|B> <sha256> (the printed diff on stdin) | hevy bootstrap
        '';
        stdin = true;
        rules =
          verbs both false [
            [ "workouts" ]
            [ "history" ]
            [ "templates" ]
            [ "routines" ]
            [ "folders" ]
            [
              "routine"
              "draft"
            ]
            [
              "routine"
              "diff"
            ]
          ]
          ++
            map
              (match: {
                inherit match;
                lanes = both;
                taints = true;
              })
              [
                [
                  "workout"
                  "*"
                ]
                [
                  "routine"
                  "*"
                ]
              ]
          ++
            map
              (match: {
                inherit match;
                lanes = interactive;
                taints = true;
                egress = true;
              })
              [
                [
                  "routine"
                  "apply"
                  "*"
                  "*"
                ]
                [ "bootstrap" ]
              ];
        skill = ./butler-skills/hevy;
      };
    })
  ];
}
