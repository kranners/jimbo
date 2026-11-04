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
  # Archive requests, from `change archive` or a card closed on the board, and what became of them.
  archive = "${selfFix}/archive";
  archived = "${selfFix}/archived";
  dismissed = "${selfFix}/dismissed";
  # Each brief as it was asked, for the builders in flight digest, since the queued request is deleted once its session starts.
  briefs = "${selfFix}/briefs";
  inherit (config.butler.builders) digest;
  runnerHome = config.users.users.backlogic-runner.home;
  launchFrom = "${aaron}/workspace/jimbo";
  personalCooldown = "${home}/.claude-accounts/cooldown/1";
  # Butler's mood pictures, one attached to every change's DM by its state, `fixed` made for a change that landed.
  moods = ../../../assets/butler/moods;
  # The spike probe's paragraph, with this change's own key, while butler-probe.nix has it on.
  probeBrief =
    if config.butler.selfFixProbe.brief == null then
      "true"
    else
      ''${lib.getExe config.butler.selfFixProbe.brief} "$id"'';

  preamble = pkgs.writeText "butler-self-fix-preamble.md" ''
    You are a change session butler started, a cloud session that does one piece of Aaron's work and lands it. Butler is Aaron's personal assistant bot: the claude-discord-threads daemon, run on the NixOS host spike as the system user butler, configured by this jimbo flake (modules/hosts/spike/butler*.nix and butler-skills/), with its memory, skills and scheduled prompts in kranners/butler-memory and its personal data index and life command in kranners/butler, jimbo's flake input butler.
    You start in kranners/jimbo. For kranners/claude-discord-threads, kranners/butler-memory or kranners/butler, call add_repo, with access "push" for a repository you change; jimbo's flake check needs read access to kranners/butler.
    Nobody watches this session and Aaron is told when it ends, so never stop to ask.

    Aaron's request, relayed by butler, is at the end. Make the smallest change that does what it asks, in whichever repository it belongs, and land it:

    - jimbo: follow its .claude/CLAUDE.md and keep its CLAUDE.md files true in the same commit. Check with the cloud session's `nix flake check` in its .claude/CLAUDE.md. Within about 5 minutes of main moving, spike's jimbo-switch pulls it and switches spike, restarting butler only when its service changed, at once or during a live call at its next quiet moment, and a commit whose build fails is never switched to; while Aaron is on a call, spike's landing queue may hold that switch first, for a quiet moment or at most 30 minutes, and a `Land: now` line in the commit message skips the queue for a fix that cannot wait.
    - claude-discord-threads: put /opt/node24/bin first on PATH, then `npm ci && npm run typecheck && npm test`. butler-pull deploys its main within about 2 minutes and restarts butler, at once or during a live call at its next quiet moment.
    - butler-memory: plain files butler reads; butler-memory-pull brings main to spike within 5 minutes.
    - butler: follow its CLAUDE.md and check with `nix flake check`. It goes live once jimbo's lock moves: in jimbo run `nix flake update butler`, then land that on jimbo's main.

    Other changes and Aaron's own sessions change the same repositories at the same time, so coordinate with them through spike's builders in flight digest, given under "Other builders in flight" at the end of this brief and kept current, every couple of minutes, in coordination/builders.md on the main of kranners/butler-memory, which add_repo lets you read:
    - First, state your intent in one or two lines in a .builder-intent file and push it alone to your designated working branch, which the digest shows the others: `git add -f .builder-intent && git commit -m "Builder intent" && git push -u origin HEAD && git reset --hard HEAD~1`, so it never reaches main.
    - Read the digest before you edit and again right before you push or land, then rebase onto the current main of each repository you change and check again.
    - Where another fix or session changes the same file or a shared design, such as access, auth, the iPad WireGuard peer, the kanban transport or approvals, the later one reconciles with the earlier one's work, and your final summary names each conflicting or dependent fix and says how you reconciled with it.

    Rebase onto the latest origin/main and push straight to main with a plain imperative commit subject.
    If the request is unclear, would widen butler's permissions or sandbox, touches secrets, or deletes data, do not land it: push a branch named after the change and say why.
    Never print, commit or send secrets.
    When the brief gives a spike probe, verify your work on spike with it before you report done; either way, say plainly in your summary what you could not test or verify.
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

  change = pkgs.writeShellApplication {
    name = "change";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.findutils
      pkgs.gnugrep
      pkgs.gnused
      pkgs.jq
    ];
    text = ''
      usage() {
        echo "usage: change start (the request on stdin) | change status <id> | change list | change archive <id>" >&2
        exit 2
      }

      # What was done to a change from the board or by archive, for status and list.
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
          [ -e "${sessions}/$id" ] || [ -e "${queue}/$id.json" ] || { echo "No change $id." >&2; exit 1; }
          echo butler > "${archive}/$id"
          [ ! -e "${sessions}/$id" ] || touch "${refresh}/$id"
          echo "Asked spike to archive change $id; its cloud session is archived, and its card on the board marked archived, within a few minutes."
          ;;
        start)
          [ "$#" -eq 1 ] || usage
          request=$(cat)
          [ -n "''${request//[[:space:]]/}" ] || { echo "change start needs the request on stdin" >&2; exit 2; }
          id="$(date +%Y%m%d-%H%M%S)-$$"
          jq -n --arg request "$request" '{request: $request}' > "${queue}/$id.json.tmp"
          mv "${queue}/$id.json.tmp" "${queue}/$id.json"
          echo "Queued change $id. Its cloud session starts within a minute, and spike then DMs Aaron its start card with the link, so tell him in one line and leave the detail to the card; read its link with: change status $id"
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
            echo "No change $id." >&2
            exit 1
          fi
          ;;
        list)
          [ "$#" -eq 1 ] || usage
          # Every change asked for in the last 7 days, newest first, from the records start and the launcher leave behind.
          mapfile -t ids < <(find "${sessions}" "${queue}" -mindepth 1 -maxdepth 1 -mtime -7 -printf '%f\n' |
            sed 's/\.json$//' | grep -E '^[0-9]{8}-[0-9]{6}-[0-9]+$' | sort -ru || true)
          if [ "''${#ids[@]}" -eq 0 ]; then
            echo "No changes in the last 7 days."
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
            echo "Change $id"
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

  # `self-fix` is the old name of `change`: it says so in a line of its own, then runs `change` with the same arguments and stdin.
  selfFixAlias = pkgs.writeShellApplication {
    name = "self-fix";
    text = ''
      echo "(self-fix is now called change; use change next time.)"
      exec ${lib.getExe change} "$@"
    '';
  };

  # Who may run `change`, and how it is gated, which the `self-fix` alias shares exactly.
  # `start` and `archive` share the `change` area: asked once in a thread that read private data or began as a voice request or board message.
  # A change that would widen butler's reach still asks Aaron for that outcome before it lands, as its session's preamble says.
  rules = [
    {
      match = [ "start" ];
      lanes = [ "interactive" ];
      egress = true;
      grant = "change";
    }
    {
      match = [
        "status"
        "*"
      ];
      lanes = [
        "interactive"
        "cron"
      ];
    }
    {
      match = [ "list" ];
      lanes = [
        "interactive"
        "cron"
      ];
    }
    {
      match = [
        "archive"
        "*"
      ];
      lanes = [ "interactive" ];
      egress = true;
      grant = "change";
    }
  ];

  # A mood picture, inlined into a card, since render's page reaches no files or network: `fixed` for a landed change's report, `diligent` for a start.
  inlineMood =
    mood:
    pkgs.runCommand "butler-self-fix-mood-${mood}" { } ''
      printf 'data:image/webp;base64,%s' "$(base64 -w0 ${moods}/${mood}.webp)" > $out
    '';
  fixedMood = inlineMood "fixed";
  render = lib.getExe config.butler.commands.render.package;
  # Draws a card's HTML as butler, which render's outbox belongs to, printing the PNG's path.
  renderAsButler = pkgs.writeShellScript "butler-self-fix-render" ''
    exec ${pkgs.util-linux}/bin/runuser -u butler -- env HOME=${home} ${render} html 760
  '';
  # The start card, from the same style and renderer as the landed report.
  startNotice = pkgs.writeShellScript "butler-self-fix-start-notice" ''
    # butler-notify comes from the system path the launcher's unit has.
    export PATH=${
      lib.makeBinPath [
        pkgs.coreutils
        pkgs.jq
      ]
    }:$PATH
    export CARD_DIR=${./butler-self-fix} MOOD_URI=${inlineMood "diligent"} MOOD_PICTURE=${moods}/diligent.webp RENDER=${renderAsButler}
    exec ${pkgs.bash}/bin/bash ${./butler-self-fix/start-notice.sh} "$@"
  '';

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
        jq -r .request "$request" > "${briefs}/$id"
        # The digest, rebuilt now so it holds every other fix as this one starts.
        timeout 120 systemctl start butler-builders.service || true
        work=$(mktemp -d)
        chown aaron: "$work"
        {
          cat ${preamble}
          jq -r .request "$request"
          # The context pack the request is about, Butler's own systems' when it names none, as every surface reads it.
          jq '{text: .request, default: "butler"}' "$request" | ${lib.getExe config.butler.context.package} prefix | sed '1s/^/\n\n/' || true
          ${probeBrief}
          if [ -s "${digest}" ]; then
            printf '\n\nOther builders in flight (read before you edit; coordinate and rebase). You are change %s, listed as queued:\n\n' "$id"
            cat "${digest}"
          fi
        } > "$work/prompt"
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
          # The start card, with the diligent mood as its banner, or the text and the picture alone when it cannot be drawn.
          pack=$(grep -m1 -oP "^Context from Butler: spike's \\K[a-z]+(?= pack)" "$work/prompt" || true)
          ${startNotice} "$request" "$id" "https://claude.ai/code/$session" "$pack" "Started on the $(basename "$config" | sed 's/^\.claude-work$/work/; s/^\.claude$/personal/') account, running" || true
        else
          echo "Could not start a cloud session: $(sed 's/\x1b\[[0-9;?]*[a-zA-Z]//g' "$work/log" | tr -s '\r\n ' ' ' | tail -c 400)" > "${sessions}/$id"
          printf 'Change couldn'"'"'t start (%s): %s\n' "$id" "$(tail -c 300 "${sessions}/$id")" |
            butler-notify ${moods}/concerned.webp > /dev/null || true
        fi
        chown butler: "${sessions}/$id"
        rm -rf "$work" "$request"
        systemctl start --no-block butler-builders.service || true
      done
    '';
  };

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
        local id=$1 work=$2 state title link card="" mood
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
              "finished with an error") headline="Change hit a problem: $title" mood=apologetic ;;
              finished) headline="Change done: $title" mood=content ;;
              archived) headline="Change closed: $title" mood=content ;;
              *) headline="Change couldn't start: $title" mood=concerned ;;
            esac
            summary=$(sed -n 's/^Final summary[^:]*: //p' "${progress}/$id")
            [ -n "$summary" ] || [ "$state" = "''${state#failed to start: }" ] || summary=''${state#failed to start: }
            # A landed change's report becomes the standard card, rendered as butler, and the text keeps to its summary and what Aaron must do.
            if [ "$state" = finished ] &&
              jq -n --slurpfile events "$work/events" --rawfile mood ${fixedMood} --arg title "$title" \
                --rawfile css ${./butler-self-fix/card.css} -f ${./butler-self-fix/report.jq} > "$work/report.json" && [ -s "$work/report.json" ]; then
              # It landed, so it shows `fixed`: inside the card, or on its own when the card cannot be drawn.
              mood=fixed
              card=$(jq -r .html "$work/report.json" | runuser -u butler -- env HOME=${home} ${render} html 760) ||
                { echo "Could not render change $id's report card; sending the fixed picture alone" >&2; card=""; }
              summary=$(jq -r .prose "$work/report.json")
              todo=$(jq -r .todo "$work/report.json")
              [ -z "$todo" ] || summary="$summary"$'\n'"You need to: $todo"
            fi
            if [ "''${#summary}" -gt 600 ]; then summary="''${summary:0:600}…"; fi
            { echo "$headline"; [ -z "$summary" ] || echo "$summary"; echo "$link"; } | butler-notify "''${card:-${moods}/$mood.webp}" > /dev/null
            # A heads-up in his live call too, if he is on one; the DM above stays the record.
            printf '%s\n' "''${headline:0:180}" | butler-call-say --call-only > /dev/null || true
            rm -f "${watch}/$id"
            ;;
          "waiting on input"*)
            if [ "$(cat "${watch}/$id")" != "$state" ]; then
              printf 'Change needs you: %s\nIt is waiting on you to answer or approve something.\n%s\n' "$title" "$link" | butler-notify ${moods}/curious.webp > /dev/null
              printf 'A change is waiting on you: %s\n' "''${title:0:150}" | butler-call-say --urgent --call-only > /dev/null || true
              echo "$state" > "${watch}/$id"
            fi
            ;;
          *) echo "$state" > "${watch}/$id" ;;
        esac
        if [ -e "${watch}/$id" ] && [ -n "$(find "${sessions}/$id" -mmin +2880)" ]; then
          rm -f "${watch}/$id"
        fi
      }

      # Archive each change asked for, by `change archive` or a card closed on the board, retrying on the next run when claude.ai refuses.
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
              echo "Could not archive change $id: HTTP $code" >&2
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

      # A state read here reaches the builders in flight digest at once.
      systemctl start --no-block butler-builders.service || true
    '';
  };

  # Switches spike to jimbo's main, holding a switch that would restart butler in the landing queue (butler-land.nix) while Aaron is on a call.
  jimbo-switch = pkgs.writeShellApplication {
    name = "jimbo-switch";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.diffutils
      pkgs.git
      pkgs.gnugrep
      pkgs.nh
      pkgs.nix
      pkgs.openssh
      config.butler.land.package
    ];
    text = ''
      failed_record="$STATE_DIRECTORY/failed"
      # The system built ahead of a held switch, kept as a GC root, and the commit it was built from.
      system_link="$STATE_DIRECTORY/system"
      built_record="$STATE_DIRECTORY/built"
      [ "$(git branch --show-current)" = main ] || { echo "Not switching: the checkout is not on main" >&2; exit 0; }
      [ -z "$(git status --porcelain)" ] || { echo "Not switching: the checkout has uncommitted changes" >&2; exit 0; }
      git fetch --quiet origin main
      running=$(git rev-parse HEAD)
      latest=$(git rev-parse FETCH_HEAD)
      [ "$latest" != "$running" ] || exit 0
      [ "$latest" != "$(cat "$failed_record" 2>/dev/null)" ] || exit 0
      git merge-base --is-ancestor "$running" "$latest" || { echo "Not switching: $latest does not descend from $running" >&2; exit 0; }
      subject=$(git log -1 --format=%s "$latest")
      commits=$(mktemp)
      trap 'rm -f "$commits"' EXIT
      git log --no-merges --format=$'%H\t%ct\t%s' "$running..$latest" > "$commits"

      # A fix for a commit that failed to switch, or one that asks, skips the landing queue.
      urgent=""
      [ ! -s "$failed_record" ] || urgent="it follows a commit that failed to switch"
      ! git log --format=%B "$running..$latest" | grep -qiE '^Land: *now' || urgent="a commit asks to land now"

      system=""
      if [ -n "$urgent" ]; then
        butler-land gate jimbo "$running" "$latest" "$commits" unknown "$urgent" || true
      elif ! butler-land would-hold jimbo; then
        # Built first, so a held commit that fails to build is reported now rather than when it is released.
        if [ "$(cat "$built_record" 2>/dev/null)" = "$latest" ] && [ -e "$system_link" ]; then
          system=$(readlink -f "$system_link")
        elif system=$(nix build --out-link "$system_link" --print-out-paths "git+file://$PWD?rev=$latest&shallow=1#nixosConfigurations.spike.config.system.build.toplevel"); then
          echo "$latest" > "$built_record"
        else
          echo "$latest" > "$failed_record"
          butler-land failed jimbo "$latest" build "$subject"
          exit 1
        fi
        same() {
          [ ! -e "$1" ] && [ ! -e "$2" ] && return 0
          diff -rq "$1" "$2" > /dev/null 2>&1
        }
        restarts=""
        for unit in ${lib.escapeShellArgs config.butler.land.restartUnits}; do
          old=/run/current-system/etc/systemd/system/$unit
          new=$system/etc/systemd/system/$unit
          if ! same "$old" "$new" || ! same "$old.d" "$new.d"; then restarts="$restarts $unit"; fi
        done
        held=0
        butler-land gate jimbo "$running" "$latest" "$commits" "$restarts" "" || held=$?
        # 3 is held; anything else from the queue itself switches anyway, as before it existed.
        [ "$held" -ne 3 ] || exit 0
      fi

      # What this switch brings in, for butler to say why it restarted if the switch restarts it.
      git log --no-merges --format=%s "$running..$latest" > "$STATE_DIRECTORY/switching"
      git merge --quiet --ff-only "$latest"
      switch() {
        if [ -n "$system" ]; then
          # Built already, so a released landing activates in seconds, close behind its cue.
          sudo nix-env --profile /nix/var/nix/profiles/system --set "$system" && sudo "$system/bin/switch-to-configuration" switch
        else
          nh os switch .
        fi
      }
      if ! switch; then
        rm -f "$STATE_DIRECTORY/switching"
        echo "$latest" > "$failed_record"
        butler-land failed jimbo "$latest" switch "$subject"
        exit 1
      fi
      rm -f "$failed_record" "$STATE_DIRECTORY/switching"
      butler-land landed jimbo "$latest"
      # Only after a switch that worked: keep the newest system generations, the running one among them, and collect the store when a backlog of them went.
      if pruned=$(sudo /run/current-system/sw/bin/prune-generations ${toString config.jimbo.keepGenerations} /nix/var/nix/profiles/system); then
        echo "$pruned"
        count=''${pruned#Deleted }
        count=''${count%% *}
        [ "$count" -le ${toString config.jimbo.keepGenerations} ] || sudo systemctl start --no-block nix-gc.service || true
      else
        echo "Pruning old system generations failed" >&2
      fi
    '';
  };
in
{
  butler.commands.change = {
    package = change;
    description = ''
      Start a cloud Claude Code session that makes a change Aaron asks for, to butler itself (its jimbo config, the claude-discord-threads daemon or its memory) or to his other projects, and lands it, which then deploys on its own.
      change start (Aaron's request on stdin) | change status <id> (the session's link once it starts, then its live state, recent activity, branch and final summary) | change list (every change of the last 7 days, newest first, with its id, title, state, last activity and link; use it when Aaron asks how his work is going without an id) | change archive <id> (archive a change's cloud session when Aaron asks to close or stop it; its board card follows)
    '';
    stdin = true;
    inherit rules;
    skill = ./butler-skills/change;
  };

  # The old name, kept working for briefs and sessions from before the rename, with the same rules; remove it in a later change.
  butler.commands.self-fix = {
    package = selfFixAlias;
    description = ''
      Old name of change, kept working for now; use change instead.
    '';
    stdin = true;
    inherit rules;
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
    "d ${briefs} 0700 root root 7d"
    # The skill's link from before it was renamed `change`, which nothing replaces.
    "r ${home}/.claude/skills/self-fix"
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
    description = "Start the cloud sessions butler queued for Aaron's changes";
    path = [ "/run/current-system/sw" ];
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

  # Prunes once when a switch first brings it in and at boot, since the switch that deploys a new keep-count still runs the old jimbo-switch.
  systemd.services.jimbo-switch-prune = {
    description = "Keep only the newest system generations, then collect the store";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      /run/current-system/sw/bin/prune-generations ${toString config.jimbo.keepGenerations} /nix/var/nix/profiles/system
      ${config.systemd.package}/bin/systemctl start --no-block nix-gc.service
    '';
  };

  systemd.timers.jimbo-switch = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "5min";
      OnUnitInactiveSec = "5min";
    };
  };
}
