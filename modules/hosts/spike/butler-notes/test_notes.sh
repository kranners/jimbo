#!/usr/bin/env bash
# The flake check `butler-notes`: note and butler-notes-write against a scratch vault, offline.
set -euo pipefail
[ -n "${DEBUG:-}" ] && set -x
note=${1:-note.py} writer=${2:-notes_write.py}
here=$(mktemp -d)
export NOTES_DIR=$here/notes NOTES_WRITE_DIR=$here/spool NOTES_OFFLINE=1
mkdir -p "$NOTES_DIR/vault/Travel" "$NOTES_DIR/vault/.obsidian"
printf '# Tokyo\n' > "$NOTES_DIR/vault/Travel/Tokyo.md"
# IN is the request's stdin, since a pipe into run would lose $out to a subshell.
# The path unit starts the writer once a request is spooled, so start it here once the request is there.
run() {
  printf %s "${IN:-}" | "$note" "$@" > "$here/out" 2>&1 & local pid=$!
  until ls "$NOTES_WRITE_DIR"/spool/*.json > /dev/null 2>&1 || ! kill -0 $pid 2> /dev/null; do sleep 0.1; done
  "$writer"
  wait $pid || true
  out=$(cat "$here/out")
}
expect() { [[ $out == *"$1"* ]] || { echo "FAIL: wanted '$1' in: $out" >&2; exit 1; }; }

run read Travel/Tokyo; expect "sha256 "; sha=$(sed -n 2p <<<"$out" | cut -d' ' -f2)
IN=hi run create Travel/Tokyo; expect "already exists"
IN="- [ ] passport" run append "Travel/Tokyo.md"; expect "appended to Travel/Tokyo.md"
grep -q passport "$NOTES_DIR/vault/Travel/Tokyo.md"
IN="# Changed" run replace Travel/Tokyo "$sha"; expect "has changed since you read it"
run read Travel/Tokyo; sha=$(sed -n 2p <<<"$out" | cut -d' ' -f2)
IN="# Tokyo, rewritten" run replace Travel/Tokyo "$sha"; expect "replaced Travel/Tokyo.md"
before=$(grep -o 'restore Travel/Tokyo.md [0-9a-f]*' <<<"$out" | cut -d' ' -f3)
run history Travel/Tokyo; expect "Butler replace"
run restore Travel/Tokyo "$before"; expect "restored"
grep -q passport "$NOTES_DIR/vault/Travel/Tokyo.md"
IN="# Scratch" run create "Butler/Scratch test"; expect "created Butler/Scratch test.md"
IN=x run create ".obsidian/app"; expect "not a note path"
IN=x run create "../escape"; expect "not a note path"
IN=x run create "a#b"; expect "may not hold"
ln -s /etc "$NOTES_DIR/vault/link"
IN=x run create "link/passwd"; expect "goes through a link"
[ "$(wc -l < "$NOTES_DIR/writes.jsonl")" -eq 4 ]
echo "butler-notes: all passed"
