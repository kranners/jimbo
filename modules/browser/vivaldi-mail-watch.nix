{ pkgs }:
pkgs.writeShellApplication {
  name = "vivaldi-mail-watch";

  text = ''
    MAIL_DIR="$HOME/Library/Application Support/Vivaldi/Default/Mail"
    STATE_DIR="$HOME/Library/Caches/vivaldi-mail-watch"
    STALE_MINUTES=360
    RESTART_AFTER_DAYS=3

    notify() {
      /usr/bin/osascript -e "display notification \"$1\" with title \"Vivaldi Mail\""
    }

    PID="$(/usr/bin/pgrep -x Vivaldi | head -n 1 || true)"
    [ -n "$PID" ] || exit 0

    mkdir -p "$STATE_DIR"

    if [ -n "$(find "$MAIL_DIR" -name '*.eml' -mmin "-$STALE_MINUTES" -print -quit)" ]; then
      rm -f "$STATE_DIR/stale"
    elif [ ! -e "$STATE_DIR/stale" ]; then
      notify "No new mail in $((STALE_MINUTES / 60)) hours. Quit Vivaldi with ⌘Q and reopen it."
      touch "$STATE_DIR/stale"
    fi

    ELAPSED="$(/bin/ps -o etime= -p "$PID" | tr -d ' ')"
    DAYS=0
    case "$ELAPSED" in *-*) DAYS="''${ELAPSED%%-*}" ;; esac

    if [ "$DAYS" -ge "$RESTART_AFTER_DAYS" ] && [ "$(cat "$STATE_DIR/restart" 2>/dev/null || true)" != "$PID" ]; then
      notify "Vivaldi has been running for $DAYS days. Quit it with ⌘Q and reopen it to keep mail syncing."
      echo "$PID" >"$STATE_DIR/restart"
    fi

    exit 0
  '';
}
