{ config, pkgs, ... }:
let
  inherit (config.users.users.butler) home;

  # The daemon's DISCORD_CRON_DIR: links to the memory's own cron prompts beside the jobs butler made.
  cronDir = "${home}/cron";
  memoryCron = "${home}/memory/cron";
  lock = "${home}/jobs.lock";
  # Jobs Pulse replaced, kept for an instant rollback and put back on their schedule while Pulse is down.
  memory = "${home}/memory";
  archive = "${memory}/cron-archive";
  memoryLock = "${home}/memory.lock";
  fallbackState = "${home}/.local/state/pulse-fallback";
  pulseHealth = "http://127.0.0.1:18790/health";

  runtimeInputs = [
    pkgs.coreutils
    pkgs.curl
    pkgs.gawk
    pkgs.git
    pkgs.gnugrep
    pkgs.gnused
    pkgs.jq
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
             jobs archive <name> [sensor,...]   (Pulse replaced it: keep it in memory cron-archive/, stop it)
             jobs restore <name>                (roll back: put an archived job back on its schedule)
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
          if [[ $name == pulse-fallback-* ]]; then
            printf '%s (archived for Pulse, back on its old schedule while Pulse is down): %s at %s\n' "''${name#pulse-fallback-}" "$(field days "$file")" "$(field at "$file")"
            continue
          elif [[ $name == job-* ]]; then
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
        local archived=(${archive}/*.md)
        if [ "''${#archived[@]}" -gt 0 ]; then
          printf 'Archived for Pulse, in memory cron-archive/: %s\n' "$(for file in "''${archived[@]}"; do basename "$file" .md; done | paste -sd ' ')"
        fi
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

      # Commits one path in the memory under its lock; butler-memory-pull pushes it within 5 minutes.
      commit_memory() {
        local message=$1
        shift
        (
          exec 8>${memoryLock}
          flock 8
          git -C ${memory} add --all -- "$@"
          git -C ${memory} diff --cached --quiet || git -C ${memory} -c user.name=Butler -c user.email=butler@spike commit --quiet --message "$message"
        ) || fail "could not commit the memory's cron-archive; nothing was stopped"
      }

      archive_job() {
        [ $# -ge 1 ] && [ $# -le 2 ] || usage
        local name=$1 sensors=''${2-} files dest
        [[ $name =~ ^[a-z0-9][a-z0-9-]{0,39}$ ]] || usage
        [[ -z $sensors || $sensors =~ ^[a-z0-9_-]+(,[a-z0-9_-]+)*$ ]] || fail "sensors are Pulse sensor names, comma-separated"
        mapfile -t files < <(existing "$name")
        if [ "''${#files[@]}" -eq 0 ]; then
          [ ! -e "${memoryCron}/$name.md" ] || fail "$name is Aaron's prompt in memory cron/; a change session archives it with git mv cron/$name.md cron-archive/ in kranners/butler-memory"
          fail "no job named $name"
        fi
        [ "''${#files[@]}" -eq 1 ] || fail "$name has several files; remove the extra ones first"
        [[ ''${files[0]} != *.pending ]] && [ -z "$(field once "''${files[0]}")" ] || fail "$name is a one-off; remove it instead of archiving it"
        dest=${archive}/$name.md
        [ ! -e "$dest" ] || fail "$name is already archived; restore it first"
        mkdir -p ${archive}
        awk -v sensors="$sensors" -v when="$(date -Iminutes)" '
          /^---$/ && n < 2 { n++; if (n == 2) { print "archived: " when; print "archived-from: jobs"; if (sensors != "") print "pulse: " sensors } }
          { print }
        ' "''${files[0]}" >"$dest.tmp"
        mv "$dest.tmp" "$dest"
        commit_memory "Archive job $name for Pulse" "cron-archive/$name.md"
        rm -f -- "''${files[0]}"
        echo "Archived $name into memory cron-archive/ and stopped it; jobs restore $name puts it back."
      }

      restore_job() {
        [ $# -eq 1 ] || usage
        local name=$1 source file
        [[ $name =~ ^[a-z0-9][a-z0-9-]{0,39}$ ]] || usage
        source=${archive}/$name.md
        [ -f "$source" ] || fail "nothing archived as $name"
        grep -q '^archived-from: jobs$' "$source" || fail "$name was Aaron's memory cron/ prompt; a change session puts it back with git mv cron-archive/$name.md cron/ in kranners/butler-memory"
        [ -z "$(existing "$name")" ] || fail "a job named $name already runs"
        file="job-$name-$(date +%s).md"
        awk '/^---$/ { n++ } n == 1 && /^(archived|archived-from|pulse): / { next } { print }' "$source" >"$file.tmp"
        mv "$file.tmp" "$file"
        rm -f "pulse-fallback-$name.md"
        rm -f "$source"
        commit_memory "Restore job $name from cron-archive" "cron-archive/$name.md"
        echo "Restored $name: $(field days "$file") at $(field at "$file"), from its next time on."
      }

      case ''${1-} in
        list) [ $# -eq 1 ] || usage; list ;;
        add) shift; add "$@" ;;
        remove) shift; remove "$@" ;;
        archive) shift; archive_job "$@" ;;
        restore) shift; restore_job "$@" ;;
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

      # Pulse down: a job archived for Pulse goes back on its old schedule, as pulse-fallback-<name>.md, once Pulse's
      # health check has not answered for 15 minutes, or one of the sensors its archive names has failed that long,
      # and comes off again once Pulse has been well for 5 minutes. The daemon never fires a prompt the first time it
      # sees one, so a put-back job runs from its next time.
      mkdir -p ${fallbackState}
      health=$(curl -sS --max-time 5 ${pulseHealth} 2>/dev/null || true)
      answered=0
      if jq -e 'type == "object" and has("sensors")' >/dev/null 2>&1 <<<"$health"; then answered=1; fi
      notify() { if command -v butler-notify >/dev/null; then butler-notify --picture pulse-notice <<<"$1" || true; fi; }
      down=() up=()
      for source in ${archive}/*.md; do
        name=$(basename "$source" .md)
        [[ $name =~ ^[a-z0-9][a-z0-9-]{0,39}$ ]] || continue
        well=1
        if [ "$answered" = 0 ]; then
          well=0
        else
          IFS=, read -r -a sensors <<<"$(field pulse "$source")"
          for sensor in "''${sensors[@]}"; do
            [ -n "$sensor" ] || continue
            jq -e --arg s "$sensor" '.sensors[$s].ok == true' >/dev/null <<<"$health" || well=0
          done
        fi
        since=${fallbackState}/$name.down
        back=${fallbackState}/$name.up
        link=pulse-fallback-$name.md
        if [ "$well" = 0 ]; then
          rm -f "$back"
          [ -e "$since" ] || echo "$now" >"$since"
          if [ ! -L "$link" ] && [ $((now - $(cat "$since"))) -ge 900 ]; then
            ln -s "$source" "$link"
            logger -t butler-jobs "Pulse unwell for 15 minutes; put $name back on its old schedule"
            down+=("$name")
          fi
        else
          rm -f "$since"
          if [ -L "$link" ]; then
            [ -e "$back" ] || echo "$now" >"$back"
            if [ $((now - $(cat "$back"))) -ge 300 ]; then
              rm -f "$link" "$back"
              logger -t butler-jobs "Pulse well again; took $name off its old schedule"
              up+=("$name")
            fi
          fi
        fi
      done
      # A fallback whose archive is gone, restored or cut for good, comes off at once.
      for link in pulse-fallback-*.md; do
        [ -e "${archive}/''${link#pulse-fallback-}" ] || rm -f "$link"
      done
      for mark in ${fallbackState}/*.down ${fallbackState}/*.up; do
        name=$(basename "''${mark%.*}")
        [ -e "${archive}/$name.md" ] || rm -f "$mark"
      done
      if [ "''${#down[@]}" -gt 0 ]; then
        notify "Pulse has been down or failing for 15 minutes, so I put these jobs back on their old schedule until it recovers: ''${down[*]}."
      fi
      if [ "''${#up[@]}" -gt 0 ]; then
        notify "Pulse is well again, so these jobs are back on Pulse alone: ''${up[*]}."
      fi
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
      jobs list | jobs add <name> <daily|weekdays|weekends|mon,wed,...> <HH:MM> | jobs add <name> once <YYYY-MM-DD|today|tomorrow> <HH:MM> | jobs remove <name> | jobs archive <name> [sensor,...] | jobs restore <name>
      add takes the prompt on stdin; archive keeps a job Pulse replaced in memory cron-archive/ and stops it, restore puts it back.
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
      {
        match = [
          "archive"
          "**"
        ];
        lanes = both;
        acts = true;
      }
      {
        match = [
          "restore"
          "*"
        ];
        lanes = both;
        acts = true;
      }
    ];
    skill = ./butler-skills/jobs;
  };

  systemd.services.butler-jobs = {
    description = "Link butler's memory cron prompts beside its own jobs, show and expire its one-off jobs, and put archived jobs back while Pulse is down";
    path = [ "/run/current-system/sw" ];
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
