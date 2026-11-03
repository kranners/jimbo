{
  config,
  pkgs,
  lib,
  ...
}:
let
  inherit (config.users.users.butler) home;
  aaron = config.users.users.aaron.home;

  selfFix = "${home}/self-fix";
  queue = "${selfFix}/queue";
  sessions = "${selfFix}/sessions";
  refresh = "${selfFix}/refresh";
  progress = "${selfFix}/progress";
  watch = "${selfFix}/watch";
  # Archive requests, from `self-fix archive` or a card closed on the board, and what became of them.
  archive = "${selfFix}/archive";
  archived = "${selfFix}/archived";
  dismissed = "${selfFix}/dismissed";
  runnerHome = config.users.users.backlogic-runner.home;
  launchFrom = "${aaron}/workspace/jimbo";
  personalCooldown = "${home}/.claude-accounts/cooldown/1";

  preamble = pkgs.writeText "butler-self-fix-preamble.md" ''
    You are butler's self-fix session. Butler is Aaron's personal assistant bot: the claude-discord-threads daemon, run on the NixOS host spike as the system user butler, configured by this jimbo flake (modules/hosts/spike/butler*.nix and butler-skills/), with its memory, skills and scheduled prompts in kranners/butler-memory and its personal data index and life command in kranners/butler, jimbo's flake input butler.
    You start in kranners/jimbo. For kranners/claude-discord-threads, kranners/butler-memory or kranners/butler, call add_repo, with access "push" for a repository you change; jimbo's flake check needs read access to kranners/butler.
    Nobody watches this session and Aaron is told when it ends, so never stop to ask.

    Aaron's request, relayed by butler, is at the end. Make the smallest change that does what it asks, in whichever repository it belongs, and land it:

    - jimbo: follow its .claude/CLAUDE.md and keep its CLAUDE.md files true in the same commit. Check with the cloud session's `nix flake check` in its .claude/CLAUDE.md. Within about 5 minutes of main moving, spike's jimbo-switch pulls it and switches spike, restarting butler only when its service changed, and a commit whose build fails is never switched to.
    - claude-discord-threads: put /opt/node24/bin first on PATH, then `npm ci && npm run typecheck && npm test`. butler-pull deploys its main within about 2 minutes and restarts butler.
    - butler-memory: plain files butler reads; butler-memory-pull brings main to spike within 5 minutes.
    - butler: follow its CLAUDE.md and check with `nix flake check`. It goes live once jimbo's lock moves: in jimbo run `nix flake update butler`, then land that on jimbo's main.

    Rebase onto the latest origin/main and push straight to main with a plain imperative commit subject.
    If the request is unclear, would widen butler's permissions or sandbox, touches secrets, or deletes data, do not land it: push a branch named after the change and say why.
    Never print, commit or send secrets.
    Finish with a short summary, which is DMed to Aaron to read on his phone: two to four sentences of plain Australian English saying what changed or what went wrong, whether he needs to do anything, and when it goes live, with no step lists, branch names, commit hashes, file paths or tool names, unless something failed and he needs one, then in one short sentence.
    When you landed a change, end that message with these seven lines, which butler draws into the picture card it sends Aaron with the summary, each in a few plain words, after the summary and with nothing after them:
    Changed: what changed, in one sentence
    Before: how butler behaved before, in one short sentence
    After: how it behaves now, in one short sentence
    Ready: what Aaron can use now, separated by semicolons
    Go live: when it goes live, such as within 5 minutes, once spike switches
    Aaron must: each login, approval or hand step he must take before it works, separated by semicolons, or nothing
    Commit: the repository and short commit

    Aaron's request:

  '';

  self-fix = pkgs.writeShellApplication {
    name = "self-fix";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.findutils
      pkgs.gnugrep
      pkgs.gnused
      pkgs.jq
    ];
    text = ''
      usage() {
        echo "usage: self-fix start (the request on stdin) | self-fix status <id> | self-fix list | self-fix archive <id>" >&2
        exit 2
      }

      # What was done to a fix from the board or by archive, for status and list.
      closed() {
        cat "${archived}/$1" "${dismissed}/$1" 2>/dev/null || true
        if [ -e "${archive}/$1" ] && [ ! -e "${archived}/$1" ]; then
          echo "Archive requested; spike archives its cloud session within a few minutes."
        fi
      }

      case "''${1:-}" in
        archive)
          [ "$#" -eq 2 ] || usage
          id=$2
          [[ "$id" =~ ^[0-9]{8}-[0-9]{6}-[0-9]+$ ]] || usage
          if [ -e "${archived}/$id" ]; then
            cat "${archived}/$id"
            exit 0
          fi
          [ -e "${sessions}/$id" ] || [ -e "${queue}/$id.json" ] || { echo "No self-fix $id." >&2; exit 1; }
          echo butler > "${archive}/$id"
          [ ! -e "${sessions}/$id" ] || touch "${refresh}/$id"
          echo "Asked spike to archive self-fix $id; its cloud session is archived, and its card on the board marked archived, within a few minutes."
          ;;
        start)
          [ "$#" -eq 1 ] || usage
          request=$(cat)
          [ -n "''${request//[[:space:]]/}" ] || { echo "self-fix start needs the request on stdin" >&2; exit 2; }
          id="$(date +%Y%m%d-%H%M%S)-$$"
          jq -n --arg request "$request" '{request: $request}' > "${queue}/$id.json.tmp"
          mv "${queue}/$id.json.tmp" "${queue}/$id.json"
          echo "Queued self-fix $id. Its cloud session starts within a minute; read its link with: self-fix status $id"
          ;;
        status)
          [ "$#" -eq 2 ] || usage
          id=$2
          [[ "$id" =~ ^[0-9]{8}-[0-9]{6}-[0-9]+$ ]] || usage
          if [ -e "${sessions}/$id" ]; then
            cat "${sessions}/$id"
            closed "$id"
            grep -q '^Started ' "${sessions}/$id" || exit 0
            # butler-self-fix-progress reads the session as root, so the token never reaches butler.
            asked=$(date +%s)
            touch "${refresh}/$id"
            for _ in $(seq 30); do
              if [ -e "${progress}/$id" ] && [ "$(stat -c %Y "${progress}/$id")" -ge "$asked" ]; then
                cat "${progress}/$id"
                exit 0
              fi
              sleep 1
            done
            if [ -e "${progress}/$id" ]; then
              echo "Could not refresh the progress; as of $(date -d "@$(stat -c %Y "${progress}/$id")" '+%H:%M'):"
              cat "${progress}/$id"
            else
              echo "Could not read the session's progress yet; try again in a minute."
            fi
          elif [ -e "${queue}/$id.json" ]; then
            echo "Still starting."
          else
            echo "No self-fix $id." >&2
            exit 1
          fi
          ;;
        list)
          [ "$#" -eq 1 ] || usage
          # Every self-fix asked for in the last 7 days, newest first, from the records start and the launcher leave behind.
          mapfile -t ids < <(find "${sessions}" "${queue}" -mindepth 1 -maxdepth 1 -mtime -7 -printf '%f\n' |
            sed 's/\.json$//' | grep -E '^[0-9]{8}-[0-9]{6}-[0-9]+$' | sort -ru || true)
          if [ "''${#ids[@]}" -eq 0 ]; then
            echo "No self-fixes in the last 7 days."
            exit 0
          fi
          asked=$(date +%s)
          started=()
          for id in "''${ids[@]}"; do
            if [ -e "${sessions}/$id" ] && grep -q '^Started ' "${sessions}/$id"; then
              started+=("$id")
              touch "${refresh}/$id"
            fi
          done
          for _ in $(seq 30); do
            fresh=1
            for id in "''${started[@]}"; do
              if [ ! -e "${progress}/$id" ] || [ "$(stat -c %Y "${progress}/$id")" -lt "$asked" ]; then
                fresh=0
                break
              fi
            done
            [ "$fresh" = 0 ] || break
            sleep 1
          done
          for id in "''${ids[@]}"; do
            echo "Self-fix $id"
            if [ ! -e "${sessions}/$id" ]; then
              echo "State: still starting"
            elif ! grep -q '^Started ' "${sessions}/$id"; then
              echo "State: failed to start"
              cat "${sessions}/$id"
            else
              if [ -e "${progress}/$id" ]; then
                grep -E '^(State|Title|Last activity): ' "${progress}/$id" || true
                [ "$(stat -c %Y "${progress}/$id")" -ge "$asked" ] ||
                  echo "(as of $(date -d "@$(stat -c %Y "${progress}/$id")" '+%a %H:%M'); could not refresh it)"
              else
                echo "State: unknown, its progress could not be read yet"
              fi
              grep -oE 'https://claude.ai/code/session_[A-Za-z0-9]+' "${sessions}/$id" | sed 's/^/Link: /'
            fi
            closed "$id"
            echo
          done
          ;;
        *) usage ;;
      esac
    '';
  };

  cloudFromFile = pkgs.writeShellScript "claude-cloud-from-file" ''
    exec ${lib.getExe pkgs.claude-code} --cloud="$(cat "$1")" --permission-mode auto
  '';

  launch = pkgs.writeShellApplication {
    name = "butler-self-fix";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.gnused
      pkgs.jq
      pkgs.util-linux
    ];
    text = ''
      configDir() {
        if [ "$(cat "${personalCooldown}" 2>/dev/null || echo 0)" -gt "$(date +%s)" ]; then
          echo "${aaron}/.claude-work"
        else
          echo "${aaron}/.claude"
        fi
      }

      # The personal account is claude's default, so its state sits beside ~/.claude, and naming it in CLAUDE_CONFIG_DIR would move that state inside.
      statePath() {
        if [ "$1" = "${aaron}/.claude" ]; then
          echo "${aaron}/.claude.json"
        else
          echo "$1/.claude.json"
        fi
      }

      configOverride() {
        if [ "$1" != "${aaron}/.claude" ]; then
          echo "CLAUDE_CONFIG_DIR=$1"
        fi
      }

      trust() {
        local state
        state=$(statePath "$1")
        if [ "$(jq -r --arg dir "${launchFrom}" '.projects[$dir].hasTrustDialogAccepted // false' "$state")" != true ]; then
          jq --arg dir "${launchFrom}" '.projects[$dir].hasTrustDialogAccepted = true' "$state" > "$state.tmp"
          chown --reference="$state" "$state.tmp"
          chmod --reference="$state" "$state.tmp"
          mv "$state.tmp" "$state"
        fi
      }

      for request in "${queue}"/*.json; do
        [ -e "$request" ] || continue
        id=$(basename "$request" .json)
        # Archived before it started, from the board or by butler, so it never starts.
        if [ -e "${archive}/$id" ]; then
          echo "Archived before its cloud session started." > "${sessions}/$id"
          echo "Archived $(date '+%a %-d %b %H:%M') before it started." > "${archived}/$id"
          chown butler: "${sessions}/$id" "${archived}/$id"
          rm -f "$request" "${archive}/$id"
          continue
        fi
        work=$(mktemp -d)
        chown aaron: "$work"
        { cat ${preamble}; jq -r .request "$request"; } > "$work/prompt"
        config=$(configDir)
        trust "$config"
        (
          cd "${launchFrom}"
          # claude --cloud refuses without a terminal, so script gives it one; it stays attached, so timeout ends it once the session exists.
          # shellcheck disable=SC2046
          timeout 60 runuser -u aaron -- env HOME=${aaron} $(configOverride "$config") \
            script -q -c "${cloudFromFile} $work/prompt" "$work/log" < /dev/null > /dev/null 2>&1 || true
        )
        session=$(sed 's/\x1b\[[0-9;?]*[a-zA-Z]//g' "$work/log" | grep -aoE 'session_[A-Za-z0-9]+' | head -1 || true)
        if [ -n "$session" ]; then
          echo "Started https://claude.ai/code/$session on $(basename "$config")" > "${sessions}/$id"
          touch "${watch}/$id"
        else
          echo "Could not start a cloud session: $(sed 's/\x1b\[[0-9;?]*[a-zA-Z]//g' "$work/log" | tr -s '\r\n ' ' ' | tail -c 400)" > "${sessions}/$id"
        fi
        chown butler: "${sessions}/$id"
        rm -rf "$work" "$request"
      done
    '';
  };

  # The fixed mood picture, inlined into each report card, since render's page reaches no files or network.
  fixedMood = pkgs.runCommand "butler-self-fix-mood" { } ''
    printf 'data:image/webp;base64,%s' "$(base64 -w0 ${../../../assets/butler/moods/fixed.webp})" > $out
  '';
  render = lib.getExe config.butler.commands.render.package;

  # Turns a cloud session and its newest events, from /v1/code/sessions, into the summary butler reads.
  summarise = pkgs.writeText "butler-self-fix-progress.jq" ''
    def clip($n): tostring | gsub("\\s+"; " ") | if length > $n then .[:$n] + "…" else . end;
    def step:
      if .type == "text" then "said: " + (.text | clip(300))
      elif .type == "tool_use" then
        "ran " + .name + ": "
        + ((.input.description // .input.command // .input.file_path // .input.pattern // .input.url // .input) | clip(200))
      else empty end;
    ($session[0] | .response_shape // .session // .) as $s
    | [($events[0].data // [])[] | .payload | select(type == "object")] as $newest
    | ($newest | map(select(.type == "result")) | first) as $result
    | ($newest | map(select(.type == "assistant" or .type == "result")) | first) as $last
    | ($s.external_metadata.pending_action.tool_name // null) as $pending
    | (if $s.status == "archived" then "archived"
       elif ($s.startup_failure // null) != null then "failed to start: " + ($s.startup_failure | clip(300))
       elif $s.worker_status == "requires_action" then "waiting on input" + (if $pending then " (" + $pending + ")" else "" end)
       elif $s.worker_status == "running" then "running"
       elif $last.type == "result" then (if $last.is_error then "finished with an error" else "finished" end)
       else ($s.worker_status // $s.status // "unknown") end) as $state
    | [
        "State: " + $state,
        "Title: " + ($s.title // "untitled"),
        "Last activity: " + ($s.last_event_at // $s.updated_at // $s.created_at // "unknown"),
        ($s.config.outcomes // [] | map(select(.type == "git_repository") | .git_info | "Branch: " + ((.repo // .url // "") | tostring) + " " + ((.branches // []) | map(if type == "object" then (.name // tojson) else tostring end) | join(", "))) | .[]),
        "Recent activity, oldest first:",
        ($newest | map(select(.type == "assistant") | [.message.content[]? | step] | reverse | .[]) | .[:12] | reverse | map("- " + .) | .[]),
        (if $result then "Final summary" + (if $result.is_error then " (error)" else "" end) + ": " + (($result.result // $result.subtype // "") | clip(1500)) else empty end)
      ]
    | join("\n")
  '';

  readProgress = pkgs.writeShellApplication {
    name = "butler-self-fix-progress";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.curl
      pkgs.findutils
      pkgs.gnugrep
      pkgs.gnused
      pkgs.jq
      pkgs.util-linux
    ];
    text = ''
      # The freshest login for the account the session started on: aaron's, or the runner's, which its own sessions keep fresh.
      token() {
        local dir=$1
        jq -rs 'map(.claudeAiOauth // empty) | max_by(.expiresAt // 0) | .accessToken // empty' \
          "${aaron}/$dir/.credentials.json" "${runnerHome}/$dir/.credentials.json" 2>/dev/null || true
      }

      fetch() {
        curl --silent --show-error --max-time 15 --output "$2" --write-out '%{http_code}' \
          --header @<(printf 'Authorization: Bearer %s\n' "$bearer") \
          --header 'anthropic-version: 2023-06-01' \
          --header 'User-Agent: claude-cli/${pkgs.claude-code.version} (external, cli)' \
          "https://api.anthropic.com/v1/code/sessions/$cse$1"
      }

      tell_aaron_when_ended_or_waiting() {
        local id=$1 work=$2 state title link card=""
        # Aaron closed or marked it done himself, so nothing more is reported.
        if [ -e "${archived}/$id" ] || [ -e "${dismissed}/$id" ]; then
          rm -f "${watch}/$id"
          return
        fi
        state=$(sed -n 's/^State: //p' "${progress}/$id")
        title=$(sed -n 's/^Title: //p' "${progress}/$id")
        link=$(grep -oE 'https://claude.ai/code/session_[A-Za-z0-9]+' "${sessions}/$id")
        case "$state" in
          finished* | archived | "failed to start"*)
            # A few plain lines for his phone: what happened, the session's own short summary, clipped, and the link.
            case "$state" in
              "finished with an error") headline="Self-fix hit a problem: $title" ;;
              finished) headline="Self-fix done: $title" ;;
              archived) headline="Self-fix closed: $title" ;;
              *) headline="Self-fix couldn't start: $title" ;;
            esac
            summary=$(sed -n 's/^Final summary[^:]*: //p' "${progress}/$id")
            [ -n "$summary" ] || [ "$state" = "''${state#failed to start: }" ] || summary=''${state#failed to start: }
            # A landed fix's report becomes the standard card, rendered as butler, and the text keeps to its summary and what Aaron must do.
            if [ "$state" = finished ] &&
              jq -n --slurpfile events "$work/events" --rawfile mood ${fixedMood} --arg title "$title" \
                -f ${./butler-self-fix/report.jq} > "$work/report.json" && [ -s "$work/report.json" ]; then
              card=$(jq -r .html "$work/report.json" | runuser -u butler -- env HOME=${home} ${render} html 760) || card=""
              summary=$(jq -r .prose "$work/report.json")
              todo=$(jq -r .todo "$work/report.json")
              [ -z "$todo" ] || summary="$summary"$'\n'"You need to: $todo"
            fi
            if [ "''${#summary}" -gt 600 ]; then summary="''${summary:0:600}…"; fi
            { echo "$headline"; [ -z "$summary" ] || echo "$summary"; echo "$link"; } | butler-notify ''${card:+"$card"} > /dev/null
            rm -f "${watch}/$id"
            ;;
          "waiting on input"*)
            if [ "$(cat "${watch}/$id")" != "$state" ]; then
              printf 'Self-fix needs you: %s\nIt is waiting on you to answer or approve something.\n%s\n' "$title" "$link" | butler-notify > /dev/null
              echo "$state" > "${watch}/$id"
            fi
            ;;
          *) echo "$state" > "${watch}/$id" ;;
        esac
        if [ -e "${watch}/$id" ] && [ -n "$(find "${sessions}/$id" -mmin +2880)" ]; then
          rm -f "${watch}/$id"
        fi
      }

      # Archive each fix asked for, by `self-fix archive` or a card closed on the board, retrying on the next run when claude.ai refuses.
      for request in "${archive}"/*; do
        [ -e "$request" ] || continue
        id=$(basename "$request")
        [[ "$id" =~ ^[0-9]{8}-[0-9]{6}-[0-9]+$ ]] || { rm -f "$request"; continue; }
        # Still queued: the launcher archives it instead of starting it.
        [ -e "${sessions}/$id" ] || continue
        if [ "$(cat "$request")" = board ]; then from="from the board"; else from="by butler"; fi
        started=$(cat "${sessions}/$id")
        session=$(grep -oE 'session_[A-Za-z0-9]+' <<< "$started" | head -1 || true)
        if [ -n "$session" ]; then
          dir=$(grep -oE 'on \.claude(-work)?$' <<< "$started" | cut -c4- || true)
          bearer=$(token "''${dir:-.claude}")
          code=$(curl --silent --max-time 15 --output /dev/null --write-out '%{http_code}' --request POST \
            --header @<(printf 'Authorization: Bearer %s\n' "$bearer") \
            --header 'anthropic-version: 2023-06-01' \
            --header 'content-type: application/json' \
            --header 'User-Agent: claude-cli/${pkgs.claude-code.version} (external, cli)' \
            --data '{}' "https://api.anthropic.com/v1/code/sessions/cse_''${session#session_}/archive" || true)
          case "$code" in
            200 | 409) ;;
            *)
              echo "Could not archive self-fix $id: HTTP $code" >&2
              continue
              ;;
          esac
        fi
        echo "Archived $(date '+%a %-d %b %H:%M') $from." > "${archived}/$id"
        chown butler: "${archived}/$id"
        rm -f "$request" "${watch}/$id"
        touch "${refresh}/$id"
      done

      find "${refresh}" "${watch}" -mindepth 1 -printf '%f\n' | sort -u | while read -r id; do
        rm -f "${refresh}/$id"
        [[ "$id" =~ ^[0-9]{8}-[0-9]{6}-[0-9]+$ ]] || continue
        started=$(cat "${sessions}/$id" 2>/dev/null || true)
        session=$(grep -oE 'session_[A-Za-z0-9]+' <<< "$started" | head -1 || true)
        [ -n "$session" ] || continue
        dir=$(grep -oE 'on \.claude(-work)?$' <<< "$started" | cut -c4- || true)
        work=$(mktemp -d)
        cse="cse_''${session#session_}"
        bearer=$(token "''${dir:-.claude}")
        if [ -z "$bearer" ]; then
          echo "Could not read the session: no Claude login for $dir." > "$work/out"
        elif code=$(fetch "" "$work/session") && [ "$code" != 200 ]; then
          echo "Could not read the session: HTTP $code." > "$work/out"
        else
          code=$(fetch "/events?limit=100&sort_order=desc" "$work/events" || true)
          [ "$code" = 200 ] || echo '{}' > "$work/events"
          jq -nr --slurpfile session "$work/session" --slurpfile events "$work/events" -f ${summarise} > "$work/out" ||
            echo "Could not summarise the session." > "$work/out"
        fi
        chown butler: "$work/out"
        mv "$work/out" "${progress}/$id"
        [ ! -e "${watch}/$id" ] || tell_aaron_when_ended_or_waiting "$id" "$work"
        rm -rf "$work"
      done
    '';
  };

  jimbo-switch = pkgs.writeShellApplication {
    name = "jimbo-switch";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.git
      pkgs.nh
      pkgs.nix
      pkgs.openssh
    ];
    text = ''
      failed_record="$STATE_DIRECTORY/failed"
      [ "$(git branch --show-current)" = main ] || { echo "Not switching: the checkout is not on main" >&2; exit 0; }
      [ -z "$(git status --porcelain)" ] || { echo "Not switching: the checkout has uncommitted changes" >&2; exit 0; }
      git fetch --quiet origin main
      running=$(git rev-parse HEAD)
      latest=$(git rev-parse FETCH_HEAD)
      [ "$latest" != "$running" ] || exit 0
      [ "$latest" != "$(cat "$failed_record" 2>/dev/null)" ] || exit 0
      git merge-base --is-ancestor "$running" "$latest" || { echo "Not switching: $latest does not descend from $running" >&2; exit 0; }
      git merge --quiet --ff-only "$latest"
      if ! nh os switch .; then
        echo "$latest" > "$failed_record"
        exit 1
      fi
      rm -f "$failed_record"
    '';
  };
in
{
  butler.commands.self-fix = {
    package = self-fix;
    description = ''
      Ask a cloud Claude Code session to fix or change butler itself (its jimbo config, the claude-discord-threads daemon or its memory) and land the fix, which then deploys on its own.
      self-fix start (Aaron's request on stdin) | self-fix status <id> (the session's link once it starts, then its live state, recent activity, branch and final summary) | self-fix list (every self-fix of the last 7 days, newest first, with its id, title, state, last activity and link; use it when Aaron asks how his fixes are going without an id) | self-fix archive <id> (archive a fix's cloud session when Aaron asks to close or stop it; its board card follows)
    '';
    stdin = true;
    rules = [
      {
        match = [ "start" ];
        lanes = [ "interactive" ];
        egress = true;
      }
      {
        match = [
          "status"
          "*"
        ];
        lanes = [ "interactive" ];
      }
      {
        match = [ "list" ];
        lanes = [ "interactive" ];
      }
      {
        match = [
          "archive"
          "*"
        ];
        lanes = [ "interactive" ];
        egress = true;
      }
    ];
    skill = ./butler-skills/self-fix;
  };

  systemd.tmpfiles.rules = [
    "d ${selfFix} 0700 butler butler -"
    "d ${queue} 0700 butler butler -"
    "d ${sessions} 0700 butler butler -"
    "d ${refresh} 0700 butler butler -"
    "d ${progress} 0700 butler butler -"
    "d ${watch} 0700 root root -"
    "d ${archive} 0700 butler butler -"
    "d ${archived} 0700 butler butler -"
    "d ${dismissed} 0700 butler butler -"
  ];

  systemd.paths.butler-self-fix-progress = {
    wantedBy = [ "paths.target" ];
    pathConfig.DirectoryNotEmpty = refresh;
  };

  systemd.timers.butler-self-fix-progress = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnActiveSec = "2min";
      OnUnitInactiveSec = "2min";
    };
  };

  systemd.services.butler-self-fix-progress = {
    description = "Read the progress of the cloud sessions butler asked about or started, and tell Aaron when one ends or waits on him";
    path = [ "/run/current-system/sw" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = lib.getExe readProgress;
    };
  };

  systemd.paths.butler-self-fix = {
    wantedBy = [ "paths.target" ];
    pathConfig.DirectoryNotEmpty = queue;
  };

  systemd.services.butler-self-fix = {
    description = "Start the cloud sessions butler queued to fix itself";
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = lib.getExe launch;
    };
  };

  systemd.services.jimbo-switch = {
    description = "Switch spike to jimbo's main once it moves";
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    unitConfig.ConditionPathExists = "${launchFrom}/.git";
    # It runs the switch, so a switch must never restart it midway.
    restartIfChanged = false;
    path = [ "/run/wrappers" ];
    serviceConfig = {
      Type = "oneshot";
      User = "aaron";
      WorkingDirectory = launchFrom;
      StateDirectory = "jimbo-switch";
      ExecStart = lib.getExe jimbo-switch;
    };
  };

  systemd.timers.jimbo-switch = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "5min";
      OnUnitInactiveSec = "5min";
    };
  };
}
