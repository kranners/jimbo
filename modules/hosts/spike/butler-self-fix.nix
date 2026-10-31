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
      self-fix start (Aaron's request on stdin) | self-fix status <id> (the session's link once it starts)
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
  ];

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
