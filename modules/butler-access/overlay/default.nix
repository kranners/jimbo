# Butler's on-screen overlay for the Macs: Butler in a porthole at the top right, with his narration in speech bubbles
# under him, while butler on spike drives the Mac or works on anything at all. Spike's `mac` drives it over ssh with
# `butler-overlay`, and so does spike's overlay relay while any of butler's turns runs, with `work` every few seconds
# and `rest` once none does; each writes an event and touches `active`, and butler's Hammerspoon helper, which checks
# for it every second, starts the launcher below, which draws them with ./overlay.js and exits once butler is done, or
# after `idle` seconds with no event, so it never outlives a crashed or interrupted turn. Hammerspoon starts it, not a
# LaunchAgent, because on pilot launchd's every run of it ended killed with SIGKILL before it drew anything, while the
# same script run from a login shell stayed up.
{
  pkgs,
  lib,
  idle,
  busy,
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
    builtins.replaceStrings [ "@art@" "@idle@" ] [ "${art}" (toString idle) ] (
      builtins.readFile ./overlay.js
    )
  );

  state = ''"$HOME/.local/state/butler-overlay"'';

  # What Hammerspoon runs: it exits at once unless a session is live, and drops one that went quiet without a word.
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
    # Touched by `work` while butler's turns run: `mac`'s `hide` waits until it is BUSY seconds old, so finishing on
    # a Mac mid-turn does not fade him out while he is still working, and only `rest` or the agent's idle ends it.
    busy="$dir/busy"

    usage() {
      echo "usage: butler-overlay show | say <text> | act <text> | work [text] | rest | hide | status" >&2
      exit 2
    }

    event() {
      # A new session starts a fresh file, so the overlay never replays an old one.
      [ -e "$active" ] || : > "$events"
      printf '%s\t%s\t%s\n' "$(/bin/date +%s)" "$1" "$text" >> "$events"
      /usr/bin/touch "$active"
    }

    age() { echo $(( $(/bin/date +%s) - $(/usr/bin/stat -f %m "$1") )); }

    [ $# -ge 1 ] || usage
    verb=$1
    shift
    /bin/mkdir -p "$dir"
    # One line an event, so tabs and newlines in the text become spaces.
    text=$(printf '%s' "$*" | /usr/bin/tr '\t\r\n' '   ')

    case "$verb" in
      show | say | act) event "$verb" ;;
      work)
        /usr/bin/touch "$busy"
        if [ -n "$text" ]; then event act; else event work; fi
        ;;
      rest | hide)
        if [ "$verb" = rest ]; then
          /bin/rm -f "$busy"
        elif [ -e "$busy" ] && [ "$(age "$busy")" -le ${toString busy} ]; then
          echo "overlay: kept, butler is still working"
          exit 0
        fi
        /bin/rm -f "$active"
        printf '%s\thide\t\n' "$(/bin/date +%s)" >> "$events"
        ;;
      status)
        if [ -e "$active" ]; then
          echo "overlay: showing, last event $(age "$active") s ago"
          [ -e "$busy" ] && echo "working: last heard $(age "$busy") s ago"
        else
          echo "overlay: hidden"
        fi
        if /usr/bin/pgrep -q -f '[b]utler-overlay[.]js'; then echo "drawing: running"; else echo "drawing: not running"; fi
        /usr/bin/tail -n 3 "$HOME/Library/Logs/butler-overlay.log" 2> /dev/null | /usr/bin/sed 's/^/log: /'
        ;;
      *) usage ;;
    esac
  '';
in
{
  inherit art command launcher;
}
