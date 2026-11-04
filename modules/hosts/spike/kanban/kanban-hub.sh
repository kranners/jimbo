# kanban-hub: moves Aaron's kanban board from pilot to spike, and back, without losing or deleting anything.
# Built by modules/hosts/spike/kanban.nix, which sets HOME_DIR, MARKER, PILOT, UPDATE, LIVE_STATE, SCRATCH_STATE,
# LIVE_PORT and SCRATCH_PORT. Run as root on spike.
#
#   kanban-hub status             where the board runs and what each copy holds
#   kanban-hub backup             copy pilot's board state, on pilot and into spike's backups
#   kanban-hub counts <dir>       what a board state directory holds
#   kanban-hub snapshot-pilot     record what pilot's running board shows, for cutover to compare against
#   kanban-hub scratch            import a fresh copy of pilot's state into the scratch board on :7430 and check it
#   kanban-hub scratch-stop       stop the scratch board
#   kanban-hub token              copy the runners' shared token from pilot, if spike has none yet
#   kanban-hub cutover --yes      move the board to spike, once pilot's own board is unloaded
#   kanban-hub rollback           move the board back to pilot, keeping what spike holds

usage() {
  cat >&2 << 'EOF'
usage: kanban-hub status | backup | counts <dir> | snapshot-pilot | scratch | scratch-stop | token
                  | cutover --yes | rollback
EOF
  exit 64
}

[ "$(id -u)" = 0 ] || { echo "kanban-hub: run it as root (sudo kanban-hub ...)" >&2; exit 77; }

stamp=$(date +%Y%m%d-%H%M%S)
pilot_state='~/.local/state/kanban'

pilot() {
  ssh -F none -i /var/lib/secrets/butler-mac-key \
    -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=10 \
    -o UserKnownHostsFile=/var/lib/butler-kanban/known_hosts -o StrictHostKeyChecking=accept-new \
    "$PILOT" "$@"
}

# What a state directory holds, as one JSON object: the board's own files, parsed as the board parses them.
counts() {
  local dir=$1
  jq -n \
    --slurpfile annotations <(cat "$dir/annotations.json" 2> /dev/null || echo '{}') \
    --slurpfile regions <(cat "$dir/regions.json" 2> /dev/null || echo '[]') \
    --slurpfile comments <(cat "$dir/comments.json" 2> /dev/null || echo '[]') \
    --slurpfile layout <(cat "$dir/layout.json" 2> /dev/null || echo '{}') \
    --slurpfile relations <(cat "$dir/relations.json" 2> /dev/null || echo '[]') \
    --slurpfile colours <(cat "$dir/colours.json" 2> /dev/null || echo '{}') \
    --slurpfile butler <(cat "$dir/butler.json" 2> /dev/null || echo '{}') \
    --arg docs "$(find "$dir/docs" -type f 2> /dev/null | wc -l)" \
    --arg images "$(find "$dir/images" -type f 2> /dev/null | wc -l)" \
    --arg files "$(find "$dir" -type f 2> /dev/null | wc -l)" '
    def size: if type == "array" or type == "object" then length else 0 end;
    def values_of: if type == "object" then [.[]] elif type == "array" then . else [] end;
    ($annotations[0] | values_of) as $a |
    {
      notes: [$a[] | select(.kind == "note")] | length,
      stickers: [$a[] | select(.kind == "sticker")] | length,
      butlerCards: [$a[] | select(.kind == "butler-card")] | length,
      regions: ($regions[0] | size),
      threads: ($comments[0] | size),
      messages: ([($comments[0] | values_of)[] | (.events // []) | length] | add // 0),
      layout: ($layout[0] | size),
      relations: ($relations[0] | size),
      colours: ($colours[0] | size),
      changeActions: ($butler[0] | (.selfFixActions // {}) | size),
      docFiles: ($docs | tonumber),
      images: ($images | tonumber),
      files: ($files | tonumber)
    }'
}

# Copies pilot's state on pilot first, so the copy there is never touched again, then streams that copy here.
backup() {
  local name="kanban.backup-$stamp" out="$HOME_DIR/backups/pilot-$stamp.tar.gz"
  pilot "test -d $pilot_state && cp -a $pilot_state ~/.local/state/$name && tar -C ~/.local/state -czf - $name" > "$out.part"
  mv "$out.part" "$out"
  chmod 600 "$out"
  echo "kanban-hub: pilot's state copied to ~/.local/state/$name on pilot and $out here" >&2
  echo "$out"
}

# Unpacks a backup into an instance's state directory, setting aside, never deleting, whatever was there.
import_into() {
  local tarball=$1 target=$2 work
  work=$(mktemp -d "$HOME_DIR/backups/import.XXXXXX")
  tar -C "$work" -xzf "$tarball"
  local unpacked
  unpacked=$(find "$work" -mindepth 1 -maxdepth 1 -type d | head -n1)
  [ -n "$unpacked" ] || { echo "kanban-hub: $tarball holds no state directory" >&2; exit 1; }
  mkdir -p "$(dirname "$target")"
  if [ -e "$target" ]; then
    mv "$target" "$target.before-$stamp"
    echo "kanban-hub: what $target held is kept in $target.before-$stamp" >&2
  fi
  cp -a "$unpacked" "$target"
  chown -R kanban:kanban "$(dirname "$target")"
  local expected got
  expected=$(counts "$unpacked")
  got=$(counts "$target")
  rm -rf "$work"
  echo "kanban-hub: pilot's state holds $(jq -c . <<< "$expected")" >&2
  if [ "$(jq -S . <<< "$expected")" != "$(jq -S . <<< "$got")" ]; then
    echo "kanban-hub: the import into $target differs from pilot's state: $got" >&2
    exit 1
  fi
  echo "kanban-hub: imported into $target, every count equal: $(jq -c . <<< "$got")" >&2
}

update() {
  runuser -u kanban -- "$UPDATE" || { echo "kanban-hub: building kanban's main failed; see above" >&2; exit 1; }
  [ -e "$HOME_DIR/current/src/server/main.ts" ] || { echo "kanban-hub: no build of kanban yet" >&2; exit 1; }
  rm -f "$HOME_DIR/updated"
}

wait_up() {
  local port=$1
  for _ in $(seq 60); do
    curl -fsS --max-time 2 "http://127.0.0.1:$port/healthz" > /dev/null 2>&1 && return 0
    sleep 1
  done
  echo "kanban-hub: the board on :$port did not answer in 60 s; journalctl -u kanban*" >&2
  exit 1
}

# The notes, stickers and Butler cards a running board shows, from Butler's own board_snapshot.
snapshot_counts() {
  # The tool answers a summary line, the board as one line of JSON, then lines on Butler and Aaron.
  jq -ec '.text | split("\n")[1] | fromjson
    | { sessions: (.sessions | length), notes: (.notes | length), stickers: (.stickers | length), butlerCards: (.butlerCards | length) }'
}
snapshot_local() {
  curl -fsS --max-time 30 -H 'content-type: application/json' --data-binary '{}' \
    "http://127.0.0.1:$1/api/butler/tools/board_snapshot" | snapshot_counts
}
snapshot_pilot() {
  pilot "curl -fsS --max-time 30 -H 'content-type: application/json' --data-binary '{}' http://127.0.0.1:7420/api/butler/tools/board_snapshot" | snapshot_counts
}

# Compares what a board on spike shows with what pilot's showed: everything but the sessions, which pilot's
# runner reports again once it runs.
compare_boards() {
  local before=$1 after=$2
  echo "pilot's board showed: $before"
  echo "spike's board shows:  $after"
  if [ -z "$before" ] || [ -z "$after" ]; then
    echo "kanban-hub: one of the boards gave no snapshot to compare" >&2
    return 1
  fi
  if [ "$(jq -c 'del(.sessions)' <<< "$before")" != "$(jq -c 'del(.sessions)' <<< "$after")" ]; then
    echo "kanban-hub: the notes, stickers or Butler cards differ" >&2
    return 1
  fi
  echo "kanban-hub: the same notes, stickers and Butler cards"
}

pilot_board_loaded() {
  pilot 'launchctl print "gui/$(id -u)/kanban" > /dev/null 2>&1'
}

case "${1:-}" in
  status)
    if [ -e "$MARKER" ]; then echo "The board runs on spike (since $(stat -c %y "$MARKER"))."; else echo "The board runs on pilot, through kanban-tunnel."; fi
    systemctl --no-pager --lines=0 status kanban kanban-bridge kanban-tunnel kanban-scratch kanban-update 2> /dev/null | grep -E '^(●|○|×)|Active:' || true
    echo "Build running: $(basename "$(readlink -f "$HOME_DIR/current" 2> /dev/null || echo none)")"
    for dir in "$LIVE_STATE" "$SCRATCH_STATE"; do
      [ -d "$dir" ] && echo "$dir: $(counts "$dir" | jq -c .)"
    done
    ;;
  backup) backup > /dev/null ;;
  counts)
    [ -n "${2:-}" ] || usage
    counts "$2"
    ;;
  token)
    f=/var/lib/secrets/kanban-runner-token
    if [ -s "$f" ]; then echo "kanban-hub: spike already has the runners' token" >&2; exit 0; fi
    install -d -m 700 /var/lib/secrets
    (umask 077; pilot "grep -s '^KANBAN_RUNNER_TOKEN=' ~/.config/kanban/env | head -n1 | cut -d= -f2-" > "$f.new")
    [ -s "$f.new" ] || { rm -f "$f.new"; echo "kanban-hub: pilot's ~/.config/kanban/env has no KANBAN_RUNNER_TOKEN" >&2; exit 1; }
    mv "$f.new" "$f"
    echo "kanban-hub: copied the runners' token into $f, without printing it" >&2
    ;;
  scratch)
    tarball=$(backup)
    systemctl stop kanban-scratch 2> /dev/null || true
    import_into "$tarball" "$SCRATCH_STATE"
    update
    systemctl restart kanban-scratch
    wait_up "$SCRATCH_PORT"
    before=$(snapshot_pilot) || { echo "kanban-hub: could not read pilot's board to compare" >&2; exit 1; }
    after=$(snapshot_local "$SCRATCH_PORT")
    compare_boards "$before" "$after"
    echo "The scratch board runs on 127.0.0.1:$SCRATCH_PORT; kanban-hub scratch-stop stops it."
    ;;
  scratch-stop) systemctl stop kanban-scratch ;;
  cutover)
    [ "${2:-}" = "--yes" ] || { echo "kanban-hub: cutover moves Aaron's board to spike; run it with --yes once he has said yes" >&2; exit 64; }
    [ ! -e "$MARKER" ] || { echo "kanban-hub: the board already runs on spike" >&2; exit 0; }
    if pilot_board_loaded; then
      echo "kanban-hub: pilot's own board is still loaded; unload kanban-sync and kanban there first:" >&2
      echo '  launchctl bootout "gui/$(id -u)/kanban-sync"; launchctl bootout "gui/$(id -u)/kanban"' >&2
      exit 1
    fi
    before=$(cat "$HOME_DIR/backups/last-pilot-snapshot" 2> /dev/null || echo '')
    tarball=$(backup)
    import_into "$tarball" "$LIVE_STATE"
    update
    [ -s /var/lib/secrets/kanban-runner-token ] || "$0" token || true
    touch "$MARKER"
    systemctl stop kanban-tunnel
    systemctl start kanban kanban-bridge
    wait_up "$LIVE_PORT"
    after=$(snapshot_local "$LIVE_PORT")
    [ -z "$before" ] || compare_boards "$before" "$after" || true
    echo "kanban-hub: the board now runs on spike; kanban-hub rollback moves it back to pilot."
    ;;
  snapshot-pilot)
    # Kept for cutover to compare against, taken while pilot's board still runs.
    snapshot_pilot | tee "$HOME_DIR/backups/last-pilot-snapshot"
    ;;
  rollback)
    rm -f "$MARKER"
    systemctl stop kanban-bridge kanban 2> /dev/null || true
    systemctl start kanban-tunnel
    if [ -d "$LIVE_STATE" ]; then
      name="kanban.from-spike-$stamp"
      # Spike's state since the cutover goes beside pilot's, never over it, for Aaron to keep or drop.
      tar -C "$(dirname "$LIVE_STATE")" -czf - "$(basename "$LIVE_STATE")" \
        | pilot "mkdir -p ~/.local/state/$name && tar -C ~/.local/state/$name --strip-components 1 -xzf -" \
        && echo "kanban-hub: spike's board state is copied to ~/.local/state/$name on pilot" >&2 \
        || echo "kanban-hub: could not copy spike's state to pilot; it stays in $LIVE_STATE" >&2
    fi
    echo "kanban-hub: kanban.spike.cute.engineer goes to pilot again. Load pilot's board there:"
    echo '  launchctl bootstrap "gui/$(id -u)" ~/Library/LaunchAgents/kanban.plist; launchctl bootstrap "gui/$(id -u)" ~/Library/LaunchAgents/kanban-sync.plist'
    ;;
  *) usage ;;
esac
