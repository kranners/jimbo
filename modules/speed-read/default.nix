{ pkgs, ... }:
let
  agentRsvp = pkgs.fetchzip {
    url = "https://registry.npmjs.org/agent-rsvp/-/agent-rsvp-1.0.1.tgz";
    hash = "sha256-C9g4pe8Je4M8uNpwVQurPst5vDlg44OAyquOQguGm8w=";
  };

  readClipboard = "/usr/bin/pbpaste | ${pkgs.nodejs_24}/bin/node ${agentRsvp}/dist/index.js -w 500";
in
{
  darwinHomeModule =
    { lib, ... }:
    {
      home.file.".config/raycast/scripts/speed-read-selection.sh" = {
        executable = true;

        text = ''
          #!/bin/bash
          # @raycast.schemaVersion 1
          # @raycast.title Speed Read Selection
          # @raycast.mode silent
          # @raycast.packageName Reading

          set -euo pipefail

          wait_for_hotkey_modifiers_release() {
            /usr/bin/osascript -l JavaScript -e 'ObjC.import("AppKit"); for (let i = 0; i < 50 && ($.NSEvent.modifierFlags & 0x1E0000); i++) delay(0.02)'
          }

          wait_for_hotkey_modifiers_release
          /usr/bin/pbcopy < /dev/null
          /usr/bin/osascript -e 'tell application "System Events" to keystroke "c" using command down'

          for _ in $(seq 20); do
            [ -n "$(/usr/bin/pbpaste)" ] && break
            sleep 0.05
          done

          if [ -z "$(/usr/bin/pbpaste)" ]; then
            echo "Nothing selected"
            exit 1
          fi

          /usr/bin/osascript -l JavaScript ${./open-centred-terminal.js} '${readClipboard}; exit'
        '';
      };

      home.activation.closeTerminalWindowsOnCleanExit = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        profile=$(/usr/bin/defaults read com.apple.Terminal "Default Window Settings" 2>/dev/null || echo Basic)
        prefs=$(mktemp)
        /usr/bin/defaults export com.apple.Terminal "$prefs"

        if /usr/libexec/PlistBuddy -c "Set ':Window Settings:$profile:shellExitAction' 1" "$prefs" 2>/dev/null \
          || /usr/libexec/PlistBuddy -c "Add ':Window Settings:$profile:shellExitAction' integer 1" "$prefs" 2>/dev/null; then
          run /usr/bin/defaults import com.apple.Terminal "$prefs"
        else
          echo "Terminal has no '$profile' profile yet; open Terminal once and rebuild to close its windows on clean exit" >&2
        fi

        rm -f "$prefs"
      '';
    };
}
