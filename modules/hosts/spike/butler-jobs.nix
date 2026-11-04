{ config, pkgs, ... }:
let
  inherit (config.users.users.butler) home;

  # The daemon's DISCORD_CRON_DIR: links to the memory's own cron prompts beside the jobs butler made.
  cronDir = "${home}/cron";
  memoryCron = "${home}/memory/cron";
  lock = "${home}/jobs.lock";

  runtimeInputs = [
    pkgs.coreutils
    pkgs.gawk
    pkgs.gnugrep
    pkgs.gnused
    pkgs.util-linux
  ];

  jobs = pkgs.writeShellApplication {
    name = "jobs";
    inherit runtimeInputs;
    text = ''
      usage() {
        cat >&2 <<'EOF'
      usage: jobs list
             jobs add <name> <daily|weekdays|weekends|mon,wed,...> <HH:MM>   (the prompt on stdin)
             jobs add <name> once <YYYY-MM-DD|today|tomorrow> <HH:MM>        (the prompt on stdin)
             jobs remove <name>
      EOF
        exit 2
      }
      fail() { echo "jobs: $*" >&2; exit 2; }

      cd ${cronDir}
      exec 9>${lock}
      flock 9
      shopt -s nullglob

      field() { sed -n "/^---$/,/^---$/s/^$1: *//p" "$2" | head -n 1; }

      list() {
        local file name found=0
        for file in *.md *.md.pending; do
          found=1
          name=''${file%%.md*}
          if [[ $name == job-* ]]; then
            name=''${name#job-}
            name=''${name%-*}
            if [[ $file == *.pending ]] || [ -n "$(field once "$file")" ]; then
              printf '%s: once at %s\n' "$name" "$(date -d "@$(field once "$file")" '+%a %-d %b %Y %H:%M')"
            else
              printf '%s: %s at %s\n' "$name" "$(field days "$file")" "$(field at "$file")"
            fi
          else
            printf '%s (Aaron'"'"'s, from memory cron/, read-only): %s at %s\n' "$name" "$(field days "$file")" "$(field at "$file")"
          fi
          awk 'n >= 2 && /^This is butler.s scheduled job/ { exit } n >= 2; /^---$/ && n < 2 { n++ }' "$file" | head -c 300 | sed '/^[[:space:]]*$/d; s/^/    /'
          echo
        done
        [ "$found" = 1 ] || echo "No scheduled jobs."
      }

      existing() {
        local file
        for file in job-*.md job-*.md.pending; do
          [[ $file =~ ^job-$1-[0-9]+\.md(\.pending)?$ ]] && echo "$file"
        done
        true
      }

      add() {
        [ $# -ge 3 ] || usage
        local name=$1 days=$2 at once="" date="" due prompt file
        [[ $name =~ ^[a-z0-9][a-z0-9-]{0,39}$ ]] || fail "a name is lowercase letters, digits and dashes, at most 40 long"
        [ -z "$(existing "$name")" ] || fail "a job named $name already exists; remove it first or pick another name"

        if [ "$days" = once ]; then
          [ $# -eq 4 ] || usage
          date=$3 at=$4
          case $date in
            today | tomorrow) ;;
            *) [[ $date =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || fail "the date is YYYY-MM-DD, today or tomorrow" ;;
          esac
        else
          [ $# -eq 3 ] || usage
          at=$3
          case $days in
            daily) ;;
            weekdays) days=mon-fri ;;
            weekends) days=sat,sun ;;
            *) [[ $days =~ ^(sun|mon|tue|wed|thu|fri|sat)(,(sun|mon|tue|wed|thu|fri|sat))*$ ]] || fail "days are daily, weekdays, weekends or a list like mon,wed,fri" ;;
          esac
        fi
        [[ $at =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]] || fail "the time is HH:MM, 24-hour"

        prompt=$(head -c 4001)
        [ "$(printf %s "$prompt" | wc -c)" -le 4000 ] || fail "the prompt is over 4000 bytes; shorten it"
        [ -n "''${prompt//[[:space:]]/}" ] || fail "say on stdin what the job should do"
        ! grep -q '^---$' <<<"$prompt" || fail "the prompt may not hold a line of just ---"

        file="job-$name-$(date +%s).md"
        if [ -n "$date" ]; then
          due=$(date -d "$date $at" +%s) || fail "$date $at is not a date"
          [ "$due" -ge $(($(date +%s) + 120)) ] || fail "a one-off job must be at least 2 minutes away"
          once=$due
          days=$(date -d "@$due" +%a | tr '[:upper:]' '[:lower:]')
          # The daemon matches only time of day and weekday, so a one-off waits outside its view until the day before.
          [ "$due" -le $(($(date +%s) + 86400)) ] || file="$file.pending"
        fi

        {
          printf -- '---\ntitle: %s\nat: %s\ndays: %s\nquiet: true\n' "$name" "$at" "$days"
          [ -z "$once" ] || printf 'once: %s\n' "$once"
          printf -- '---\n%s\n\n' "$prompt"
          printf '%s\n' "This is butler's scheduled job $name, set up by Aaron in a conversation."
          printf '%s\n' "When you have finished, send Aaron the result in a few lines with \`notify\`, its text on stdin."
          printf '%s\n' "If you found nothing new he needs to hear, such as something not arrived yet, send nothing with \`notify\` and make NOTHING the last line of your reply, so this run leaves no thread behind."
        } >"$file.tmp"
        mv "$file.tmp" "$file"

        if [ -n "$once" ]; then
          echo "Scheduled $name once, at $(date -d "@$once" '+%a %-d %b %Y %H:%M')."
        else
          echo "Scheduled $name: $days at $at, from its next time on."
        fi
      }

      remove() {
        [ $# -eq 1 ] || usage
        [[ $1 =~ ^[a-z0-9][a-z0-9-]{0,39}$ ]] || usage
        local files
        mapfile -t files < <(existing "$1")
        [ "''${#files[@]}" -gt 0 ] || fail "no job named $1; Aaron's own prompts in memory cron/ are not removable here"
        rm -f -- "''${files[@]}"
        echo "Removed $1."
      }

      case ''${1-} in
        list) [ $# -eq 1 ] || usage; list ;;
        add) shift; add "$@" ;;
        remove) shift; remove "$@" ;;
        *) usage ;;
      esac
    '';
  };

  butler-jobs-tick = pkgs.writeShellApplication {
    name = "butler-jobs-tick";
    inherit runtimeInputs;
    text = ''
      cd ${cronDir}
      exec 9>${lock}
      flock 9
      shopt -s nullglob
      now=$(date +%s)

      field() { sed -n "/^---$/,/^---$/s/^$1: *//p" "$2" | head -n 1; }

      # Link the memory's cron prompts in, keeping every link that still resolves so the daemon never misses one.
      for link in *.md; do
        if [ -L "$link" ] && [ ! -e "$link" ]; then rm "$link"; fi
      done
      for prompt in ${memoryCron}/*.md; do
        name=$(basename "$prompt")
        [[ $name != job-* ]] || continue
        [ -e "$name" ] || [ -L "$name" ] || ln -s "$prompt" "$name"
      done

      # Jobs made before every job was quiet keep leaving a thread on a NOTHING answer, so make each quiet in place.
      for file in job-*.md job-*.md.pending; do
        [ -f "$file" ] && [ ! -L "$file" ] || continue
        [ -z "$(field quiet "$file")" ] || continue
        awk '
          /^---$/ && n < 2 { n++; if (n == 2) print "quiet: true" }
          { print }
          END {
            print "If you found nothing new he needs to hear, such as something not arrived yet, send nothing with `notify` and make NOTHING the last line of your reply, so this run leaves no thread behind."
          }
        ' "$file" >"$file.tmp"
        if grep -q '^quiet: true$' "$file.tmp"; then
          mv "$file.tmp" "$file"
          logger -t butler-jobs "made $file quiet"
        else
          rm -f "$file.tmp"
        fi
      done

      for file in job-*.md.pending; do
        due=$(field once "$file")
        if ! [[ $due =~ ^[0-9]+$ ]] || [ "$due" -lt "$now" ]; then
          logger -t butler-jobs "dropped $file, whose time passed before it was shown to the daemon"
          rm "$file"
        elif [ "$due" -le $((now + 86400)) ]; then
          mv "$file" "''${file%.pending}"
        fi
      done

      # A one-off has fired once its time is 10 minutes past, two dozen of the daemon's 30-second ticks.
      for file in job-*.md; do
        due=$(field once "$file")
        if [[ $due =~ ^[0-9]+$ ]] && [ "$due" -lt $((now - 600)) ]; then rm "$file"; fi
      done
    '';
  };

  both = [
    "interactive"
    "cron"
  ];
in
{
  systemd.tmpfiles.rules = [ "d ${cronDir} 0700 butler butler -" ];

  butler.commands.jobs = {
    package = jobs;
    description = ''
      Create, list and remove scheduled jobs: prompts the daemon runs in a new thread of #general at a time, which DM Aaron the result, or end with NOTHING to leave no thread when there is nothing to say.
      jobs list | jobs add <name> <daily|weekdays|weekends|mon,wed,...> <HH:MM> | jobs add <name> once <YYYY-MM-DD|today|tomorrow> <HH:MM> | jobs remove <name>
      add takes the prompt on stdin.
    '';
    stdin = true;
    rules = [
      {
        match = [ "list" ];
        lanes = both;
      }
      {
        match = [
          "add"
          "**"
        ];
        lanes = both;
        acts = true;
      }
      {
        match = [
          "remove"
          "*"
        ];
        lanes = both;
        acts = true;
      }
    ];
    skill = ./butler-skills/jobs;
  };

  systemd.services.butler-jobs = {
    description = "Link butler's memory cron prompts beside its own jobs, and show and expire its one-off jobs";
    serviceConfig = {
      Type = "oneshot";
      User = "butler";
      ExecStart = "${butler-jobs-tick}/bin/butler-jobs-tick";
    };
  };

  systemd.timers.butler-jobs = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "30s";
      OnUnitActiveSec = "1min";
    };
  };
}
