{ pkgs, ... }:
let
  agentRsvp = pkgs.fetchzip {
    url = "https://registry.npmjs.org/agent-rsvp/-/agent-rsvp-1.0.1.tgz";
    hash = "sha256-C9g4pe8Je4M8uNpwVQurPst5vDlg44OAyquOQguGm8w=";
  };

  readClipboard = "/usr/bin/pbpaste | ${pkgs.nodejs_24}/bin/node ${agentRsvp}/dist/index.js -w 400";
in
{
  darwinHomeModule.home.file.".config/raycast/scripts/speed-read-selection.sh" = {
    executable = true;

    text = ''
      #!/bin/bash
      # @raycast.schemaVersion 1
      # @raycast.title Speed Read Selection
      # @raycast.mode silent
      # @raycast.packageName Reading

      set -euo pipefail

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

      open -na Ghostty.app --args \
        --title="Speed read" \
        --window-width=60 \
        --window-height=12 \
        --quit-after-last-window-closed=true \
        -e /bin/sh -c '${readClipboard}'
    '';
  };
}
