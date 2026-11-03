# Butler's on-screen overlay for the Macs: Butler in a porthole at the top right, with his narration in speech bubbles
# under him, while butler on spike drives the Mac. Spike's `mac` drives it over ssh with `butler-overlay`, which
# writes an event and wakes the `butler-overlay` LaunchAgent; the agent draws them with ./overlay.js and exits once
# butler is done, or after `idle` seconds with no event, so it never outlives a crashed or interrupted turn.
{
  pkgs,
  lib,
  idle,
  home,
}:
let
  layers = [
    "back"
    "mask"
    "body"
    "head"
    "eye"
    "pupil"
    "brows"
    "bow"
    "rim"
    "hand-left"
    "hand-right"
  ];

  # Each layer of ./butler.svg alone, at three times its 150 by 172.5 points.
  art = pkgs.runCommand "butler-overlay-art" { nativeBuildInputs = [ pkgs.librsvg ]; } ''
    mkdir $out
    ${lib.concatMapStrings (layer: ''
      sed 's|</defs>|</defs><style>.layer { display: none } #${layer} { display: inline }</style>|' ${./butler.svg} > ${layer}.svg
      rsvg-convert --width 450 --height 518 --keep-aspect-ratio ${layer}.svg -o $out/${layer}.png
    '') layers}
  '';

  script = pkgs.writeText "butler-overlay.js" (
    builtins.replaceStrings [ "@art@" "@idle@" ] [ "${art}" (toString idle) ] (builtins.readFile ./overlay.js)
  );

  state = ''"$HOME/.local/state/butler-overlay"'';

  # The agent's program: it exits at once unless a session is live, and drops one that went quiet without a word.
  launcher = pkgs.writeShellScript "butler-overlay-agent" ''
    active=${state}/active
    [ -e "$active" ] || exit 0
    if [ $(( $(/bin/date +%s) - $(/usr/bin/stat -f %m "$active") )) -gt ${toString idle} ]; then
      /bin/rm -f "$active"
      exit 0
    fi
    exec /usr/bin/osascript -l JavaScript ${script}
  '';

  command = pkgs.writeShellScriptBin "butler-overlay" ''
    set -u
    dir=${state}
    events="$dir/events"
    active="$dir/active"
    label=butler-overlay

    usage() {
      echo "usage: butler-overlay show | say <text> | act <text> | hide | status" >&2
      exit 2
    }

    [ $# -ge 1 ] || usage
    verb=$1
    shift
    /bin/mkdir -p "$dir"
    # One line an event, so tabs and newlines in the text become spaces.
    text=$(printf '%s' "$*" | /usr/bin/tr '\t\r\n' '   ')

    case "$verb" in
      show | say | act)
        # A new session starts a fresh file, so the overlay never replays an old one.
        [ -e "$active" ] || : > "$events"
        printf '%s\t%s\t%s\n' "$(/bin/date +%s)" "$verb" "$text" >> "$events"
        /usr/bin/touch "$active"
        /bin/launchctl kickstart "gui/$(/usr/bin/id -u)/$label" > /dev/null 2>&1 || true
        ;;
      hide)
        /bin/rm -f "$active"
        printf '%s\thide\t\n' "$(/bin/date +%s)" >> "$events"
        ;;
      status)
        if [ -e "$active" ]; then
          echo "overlay: showing, last event $(( $(/bin/date +%s) - $(/usr/bin/stat -f %m "$active") )) s ago"
        else
          echo "overlay: hidden"
        fi
        echo "agent: $(/bin/launchctl print "gui/$(/usr/bin/id -u)/$label" 2> /dev/null | /usr/bin/awk '$1 == "state" { print $3; exit }' | /usr/bin/grep . || echo "not loaded")"
        ;;
      *) usage ;;
    esac
  '';
in
{
  inherit art command;

  agent = {
    enable = true;
    config = {
      Label = "butler-overlay";
      ProgramArguments = [ "${launcher}" ];
      # launchd starts it whenever a session is live, and again if it exits while one is.
      KeepAlive.PathState."${home}/.local/state/butler-overlay/active" = true;
      ThrottleInterval = 1;
      ProcessType = "Interactive";
      StandardOutPath = "${home}/Library/Logs/butler-overlay.log";
      StandardErrorPath = "${home}/Library/Logs/butler-overlay.log";
    };
  };
}
