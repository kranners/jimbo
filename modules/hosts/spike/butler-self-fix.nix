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
  runnerHome = config.users.users.backlogic-runner.home;
  launchFrom = "${aaron}/workspace/jimbo";
  personalCooldown = "${home}/.claude-accounts/cooldown/1";

  preamble = pkgs.writeText "butler-self-fix-preamble.md" ''
    You are butler's self-fix session. Butler is Aaron's personal assistant bot: the claude-discord-threads daemon, run on the NixOS host spike as the system user butler, configured by this jimbo flake (modules/hosts/spike/butler*.nix and butler-skills/), with its memory, skills and scheduled prompts in kranners/butler-memory.
    You start in kranners/jimbo. For kranners/claude-discord-threads or kranners/butler-memory, call add_repo, with access "push" for a repository you change.
    This sandbox reaches only GitHub repositories attached to it, so when nix answers 403 fetching a github: flake input, call add_repo for that input's repository and retry.

    Aaron's request, relayed by butler, is at the end. Make the smallest change that does what it asks, in whichever repository it belongs, and land it:

    - jimbo: follow its .claude/CLAUDE.md and keep its CLAUDE.md files true in the same commit. Check with `nix --extra-experimental-features 'nix-command flakes' flake check`. Within about 5 minutes of main moving, spike's jimbo-switch pulls it and switches spike, restarting butler only when its service changed, and a commit whose build fails is never switched to.
    - claude-discord-threads: put /opt/node24/bin first on PATH, then `npm ci && npm run typecheck && npm test`. butler-pull deploys its main within about 2 minutes and restarts butler.
    - butler-memory: plain files butler reads; butler-memory-pull brings main to spike within 5 minutes.

    Rebase onto the latest origin/main and push straight to main with a plain imperative commit subject.
    If the request is unclear, would widen butler's permissions or sandbox, touches secrets, or deletes data, do not land it: push a branch named after the change and say why.
    Never print, commit or send secrets.
    Finish with a short summary: what changed, the commit, and when it goes live.

    Aaron's request:

  '';

  self-fix = pkgs.writeShellApplication {
    name = "self-fix";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.jq
    ];
    text = ''
      usage() {
        echo "usage: self-fix start (the request on stdin) | self-fix status <id>" >&2
        exit 2
      }

      case "''${1:-}" in
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
        *) usage ;;
      esac
    '';
  };

  cloudFromFile = pkgs.writeShellScript "claude-cloud-from-file" ''
    exec ${lib.getExe pkgs.claude-code} --cloud="$(cat "$1")"
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

      trust() {
        local state="$1/.claude.json"
        if [ "$(jq -r --arg dir "${launchFrom}" '.projects[$dir].hasTrustDialogAccepted // false' "$state")" != true ]; then
          jq --arg dir "${launchFrom}" '.projects[$dir].hasTrustDialogAccepted = true' "$state" > "$state.tmp"
          chown aaron: "$state.tmp"
          mv "$state.tmp" "$state"
        fi
      }

      for request in "${queue}"/*.json; do
        [ -e "$request" ] || continue
        id=$(basename "$request" .json)
        work=$(mktemp -d)
        chown aaron: "$work"
        { cat ${preamble}; jq -r .request "$request"; } > "$work/prompt"
        config=$(configDir)
        trust "$config"
        (
          cd "${launchFrom}"
          # claude --cloud refuses without a terminal, so script gives it one; it stays attached, so timeout ends it once the session exists.
          timeout 60 runuser -u aaron -- env HOME=${aaron} CLAUDE_CONFIG_DIR="$config" \
            script -q -c "${cloudFromFile} $work/prompt" "$work/log" < /dev/null > /dev/null 2>&1 || true
        )
        session=$(sed 's/\x1b\[[0-9;?]*[a-zA-Z]//g' "$work/log" | grep -aoE 'session_[A-Za-z0-9]+' | head -1 || true)
        if [ -n "$session" ]; then
          echo "Started https://claude.ai/code/$session on $(basename "$config")" > "${sessions}/$id"
        else
          echo "Could not start a cloud session: $(sed 's/\x1b\[[0-9;?]*[a-zA-Z]//g' "$work/log" | tr -s '\r\n ' ' ' | tail -c 400)" > "${sessions}/$id"
        fi
        chown butler: "${sessions}/$id"
        rm -rf "$work" "$request"
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
      pkgs.gnugrep
      pkgs.jq
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

      for request in "${refresh}"/*; do
        [ -e "$request" ] || continue
        id=$(basename "$request")
        rm -f "$request"
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
      self-fix start (Aaron's request on stdin) | self-fix status <id> (the session's link once it starts, then its live state, recent activity, branch and final summary)
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
    ];
    skill = ./butler-skills/self-fix;
  };

  systemd.tmpfiles.rules = [
    "d ${selfFix} 0700 butler butler -"
    "d ${queue} 0700 butler butler -"
    "d ${sessions} 0700 butler butler -"
    "d ${refresh} 0700 butler butler -"
    "d ${progress} 0700 butler butler -"
  ];

  systemd.paths.butler-self-fix-progress = {
    wantedBy = [ "paths.target" ];
    pathConfig.DirectoryNotEmpty = refresh;
  };

  systemd.services.butler-self-fix-progress = {
    description = "Read the progress of the cloud sessions butler asked about";
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
