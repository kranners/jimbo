{
  darwinSystemModule.system.defaults.screencapture = {
    location = "~/Pictures";
    show-thumbnail = false;
  };

  darwinHomeModule =
    { config, pkgs, ... }:
    let
      screenshotFolder = "${config.home.homeDirectory}/Pictures";

      copyNewestCapture = pkgs.writeShellScript "copy-newest-capture" ''
        set -euo pipefail

        last_copied_file="${config.xdg.cacheHome}/last-copied-capture"
        newest_capture=$(/bin/ls -t "${screenshotFolder}"/Screenshot*.png "${screenshotFolder}"/Screen\ Recording*.mov 2>/dev/null | /usr/bin/head -n 1 || true)

        [ -n "$newest_capture" ] || exit 0
        [ "$newest_capture" != "$(cat "$last_copied_file" 2>/dev/null)" ] || exit 0

        case "$newest_capture" in
          *.png) clipboard_contents='read (POSIX file filePath) as «class PNGf»' ;;
          *) clipboard_contents='POSIX file filePath' ;;
        esac

        /usr/bin/osascript \
          -e 'on run argv' \
          -e 'set filePath to item 1 of argv' \
          -e "set the clipboard to ($clipboard_contents)" \
          -e 'end run' \
          "$newest_capture"

        mkdir -p "$(dirname "$last_copied_file")"
        printf '%s' "$newest_capture" > "$last_copied_file"
      '';
    in
    {
      launchd.agents.copy-captures-to-clipboard = {
        enable = true;

        config = {
          ProgramArguments = [ "${copyNewestCapture}" ];
          WatchPaths = [ screenshotFolder ];
          ThrottleInterval = 1;
        };
      };
    };
}
