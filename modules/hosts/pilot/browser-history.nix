{
  darwinHomeModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      home = config.home.homeDirectory;
      key = "${home}/.ssh/browser-history";
      logs = "${home}/Library/Logs/browser-history";
      push = pkgs.writeShellApplication {
        name = "browser-history-push";
        runtimeInputs = [
          pkgs.sqlite
          pkgs.openssh
          pkgs.coreutils
        ];
        text = ''
          support="$HOME/Library/Application Support"
          declare -A roots=(
            [chromium]="$support/Chromium"
            [chrome]="$support/Google/Chrome"
            [arc]="$support/Arc/User Data"
            [brave]="$support/BraveSoftware/Brave-Browser"
            [edge]="$support/Microsoft Edge"
            [vivaldi]="$support/Vivaldi"
          )
          snapshots=$(mktemp -d)
          trap 'rm -rf "$snapshots"' EXIT
          status=0
          for browser in "''${!roots[@]}"; do
            for history in "''${roots[$browser]}"/*/History; do
              [ -f "$history" ] || continue
              profile=$(basename "$(dirname "$history")")
              profile=''${profile//[^A-Za-z0-9_]/_}
              name="pilot-$browser-$profile.sqlite"
              snapshot="$snapshots/$name"
              if sqlite3 "file:''${history// /%20}?immutable=1" "VACUUM INTO '$snapshot'" \
                && [ "$(sqlite3 "$snapshot" "PRAGMA quick_check")" = ok ] \
                && ssh -i ${key} -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=15 \
                  -o StrictHostKeyChecking=accept-new browser-history@10.100.0.1 "$name" < "$snapshot"; then
                echo "$(date -Is) pushed $name"
              else
                echo "$(date -Is) failed $name" >&2
                status=1
              fi
            done
          done
          exit "$status"
        '';
      };
    in
    {
      home.activation.browserHistoryKey =
        lib.hm.dag.entryBetween [ "setupLaunchAgents" ] [ "writeBoundary" ]
          ''
            mkdir -p ${logs} "$(dirname ${key})"
            [ -f ${key} ] || ${pkgs.openssh}/bin/ssh-keygen -q -t ed25519 -N "" -C browser-history@pilot -f ${key}
          '';

      launchd.agents.browser-history = {
        enable = true;

        config = {
          Label = "browser-history";
          ProgramArguments = [ "${push}/bin/browser-history-push" ];
          RunAtLoad = true;
          StartCalendarInterval = [
            {
              Hour = 13;
              Minute = 0;
            }
          ];
          StandardOutPath = "${logs}/push.log";
          StandardErrorPath = "${logs}/push.log";
        };
      };
    };
}
