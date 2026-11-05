# Butler's self-check after every start: 90 seconds after butler starts, a deploy's restart above all, the daemon's
# own `npm run selfcheck` checks its controls read-only from its environment, beside a few of spike's interfaces,
# and Aaron hears of it only when something fails, once per set of failures.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  home = "/var/lib/butler";
  checkout = "${home}/claude-discord-threads";
  state = "/var/lib/butler-selfcheck";
  voice = config.butler.voice.enable;

  butler-selfcheck = pkgs.writeShellApplication {
    name = "butler-selfcheck";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.curl
      pkgs.gnugrep
      pkgs.gnused
      pkgs.nodejs_24
      pkgs.systemd
      config.butler.land.package
    ];
    text = ''
      # Reads and probes only: it sends, runs and writes nothing of butler's, and DMs Aaron only when a control fails.
      lines=$(cd ${checkout} && node src/selfcheck.ts 2>&1) || true
      lines=$(printf '%s\n' "$lines" | grep -E '^(PASS|FAIL) ' || true)
      [ -n "$lines" ] || lines="FAIL the daemon's self-check runs: npm run selfcheck printed nothing"

      check() {
        if [ "$2" = ok ]; then lines+=$'\n'"PASS $1"; else lines+=$'\n'"FAIL $1: $2"; fi
      }

      if systemctl is-active --quiet butler.service; then check "butler is running" ok; else check "butler is running" "butler.service is not active"; fi

      # The landing queue answers its status.
      if butler-land status >/dev/null 2>&1; then check "the landing queue answers" ok; else check "the landing queue answers" "land-queue status failed"; fi

      # The life explorer, whose API is behind the device gate, refuses a device it never signed in.
      code=$(curl -sk -o /dev/null -w '%{http_code}' --max-time 10 --resolve life.spike.cute.engineer:443:10.100.0.1 https://life.spike.cute.engineer/api/desk || true)
      if [ "$code" != 200 ]; then check "the life explorer stays behind its login" ok; else check "the life explorer stays behind its login" "/api/desk answered 200 without a login"; fi

      ${lib.optionalString voice ''
        # The kitchen panel's voice endpoint refuses a request without its token.
        code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 -X POST -H 'Content-Type: application/json' -d '{}' http://127.0.0.1:18789/v1/chat/completions || true)
        if [ "$code" = 401 ]; then check "the voice endpoint needs its token" ok; else check "the voice endpoint needs its token" "answered $code without one"; fi
      ''}

      printf '%s\n' "$lines"
      failed=$(printf '%s\n' "$lines" | grep '^FAIL ' || true)
      if [ -z "$failed" ]; then
        rm -f ${state}/failed
        echo "butler-selfcheck: every control passes"
        exit 0
      fi
      # Told once per set of failures, so a restart loop does not DM Aaron every few minutes.
      if [ "$failed" != "$(cat ${state}/failed 2>/dev/null)" ]; then
        printf '%s\n' "$failed" > ${state}/failed
        count=$(printf '%s\n' "$failed" | wc -l)
        printf 'Self-check after butler started: %s failed.\n%s\n' "$count" "$(printf '%s\n' "$failed" | sed 's/^FAIL /- /' | head -10)" | /run/current-system/sw/bin/butler-notify || true
      fi
      exit 1
    '';
  };
in
{
  systemd.services.butler-selfcheck = {
    description = "Check butler's controls, signals and interfaces read-only, and DM Aaron only when one fails";
    # The daemon's own environment, so it reads the manifest, attach paths and state butler reads, but none of its secrets.
    environment = removeAttrs config.systemd.services.butler.environment [ "PATH" ];
    unitConfig.ConditionPathExists = "${checkout}/.git";
    serviceConfig = {
      Type = "oneshot";
      User = "butler";
      SupplementaryGroups = [ "butler-notify" ];
      StateDirectory = baseNameOf state;
      ExecStart = lib.getExe butler-selfcheck;
      TimeoutStartSec = 120;
      # A failing control fails the unit, but the monitor's failed-unit judging waits for 3 in a row, and Aaron has had the DM.
      SuccessExitStatus = [ 1 ];
    };
  };

  # Armed afresh each time butler starts, so the check runs once the daemon has connected and written its state.
  systemd.timers.butler-selfcheck = {
    description = "Run butler's self-check 90 seconds after butler starts";
    timerConfig = {
      OnActiveSec = "90s";
      RemainAfterElapse = false;
    };
  };

  systemd.services.butler.serviceConfig.ExecStartPost = [
    "+${pkgs.systemd}/bin/systemctl restart --no-block butler-selfcheck.timer"
  ];
}
