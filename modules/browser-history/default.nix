{ host, lib, ... }:
let
  device = lib.toLower (lib.replaceStrings [ "-" ] [ "" ] host.hostname);
in
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
              name="${device}-$browser-$profile.sqlite"
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
      # Run by macOS's own /bin/bash, the agent's program, since Full Disk Access, which reading Messages needs, is
      # granted to that program by path and a store path would change on every update.
      messages = pkgs.writeShellScript "messages-history-push" ''
        set -euo pipefail
        snapshots=$(mktemp -d)
        trap 'rm -rf "$snapshots"' EXIT
        name="${device}-messages.sqlite"
        snapshot="$snapshots/$name"
        if ! ${pkgs.sqlite}/bin/sqlite3 "file:$HOME/Library/Messages/chat.db?mode=ro" "
          ATTACH '$snapshot' AS s;
          CREATE TABLE s.message AS SELECT ROWID, guid, text, attributedBody, handle_id, service, date, is_from_me, cache_has_attachments, associated_message_type FROM message;
          CREATE TABLE s.handle AS SELECT ROWID, id, service FROM handle;
          CREATE TABLE s.chat AS SELECT ROWID, guid, chat_identifier, display_name, service_name FROM chat;
          CREATE TABLE s.chat_message_join AS SELECT chat_id, message_id FROM chat_message_join;
        "; then
          echo "$(date +%FT%T%z) failed to read Messages; give /bin/bash Full Disk Access" >&2
          exit 1
        fi
        [ "$(${pkgs.sqlite}/bin/sqlite3 "$snapshot" "PRAGMA quick_check")" = ok ]
        ${pkgs.openssh}/bin/ssh -i ${key} -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=15 \
          -o StrictHostKeyChecking=accept-new browser-history@10.100.0.1 "$name" < "$snapshot"
        echo "$(date +%FT%T%z) pushed $name"
      '';
    in
    {
      home.activation.browserHistoryKey =
        lib.hm.dag.entryBetween [ "setupLaunchAgents" ] [ "writeBoundary" ]
          ''
            mkdir -p ${logs} "$(dirname ${key})"
            [ -f ${key} ] || ${pkgs.openssh}/bin/ssh-keygen -q -t ed25519 -N "" -C browser-history@${device} -f ${key}
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

      launchd.agents.messages-history = {
        enable = true;

        config = {
          Label = "messages-history";
          ProgramArguments = [
            "/bin/bash"
            "${messages}"
          ];
          RunAtLoad = true;
          StartCalendarInterval = [
            {
              Hour = 13;
              Minute = 10;
            }
          ];
          StandardOutPath = "${logs}/messages.log";
          StandardErrorPath = "${logs}/messages.log";
        };
      };
    };
}
