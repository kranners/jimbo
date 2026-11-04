# The start and landed cards and the start notice's fallback, on fixture briefs, offline: bash test-cards.sh <dir with start.jq, report.jq, card.css, start-notice.sh>
set -eu
dir=$1
work=$(mktemp -d)
fail() { echo "FAIL: $*" >&2; exit 1; }
printf 'data:image/webp;base64,AAAA' > "$work/mood"

card() {
  jq -n --arg request "$1" --arg id 20261104-125013-1839426 --arg pack butler --arg state "Started, running" \
    --rawfile mood "$work/mood" --rawfile css "$dir/card.css" -f "$dir/start.jq"
}

# Numbered steps become the breakdown, at most 5, and the banner and kicker are there.
out=$(card $'From Aaron (Wed 4 Nov 2026): \'make the start card visual\'.\n\nRepo: kranners/jimbo.\n\nDo:\n1. Draw a card.\n2. Fall back to text.\n3. Three.\n4. Four.\n5. Five.\n6. Six.\nLand it yourself; this is a feature, not an approvals change.')
[ "$(jq -r .title <<< "$out")" = "Make the start card visual." ] || fail "title: $(jq -r .title <<< "$out")"
html=$(jq -r .html <<< "$out")
grep -q 'Change started' <<< "$html" || fail "kicker"
grep -q "url('data:image/webp;base64,AAAA')" <<< "$html" || fail "banner"
[ "$(grep -o '<li>' <<< "$html" | wc -l)" = 5 ] || fail "five steps"
grep -q '<li>Draw a card.</li>' <<< "$html" || fail "first step"
! grep -q 'Six' <<< "$html" || fail "sixth step shown"
grep -q '<b>Repos:</b> jimbo<' <<< "$html" || fail "repos"
grep -q 'the butler pack' <<< "$html" || fail "pack"
grep -q 'Lands by itself' <<< "$html" || fail "said not an approvals change, flagged anyway"
grep -q '20261104-125013-1839426' <<< "$html" || fail "id"

# Unnumbered briefs take their next lines, and access changes are flagged.
html=$(card $'Open the board to the iPad.\nGive the iPad peer access to the board over WireGuard.\nKeep the device gate in front.' | jq -r .html)
grep -q '<li>Give the iPad peer access' <<< "$html" || fail "unnumbered steps"
grep -q 'may ask your yes first' <<< "$html" || fail "approval flag"

# A private brief shows only its title and repositories, never its lines or pack.
html=$(card $'Sort out the Up bank summary for butler.\n1. Show the balance of 1234.56 in the money tab.\nRepo: kranners/butler.' | jq -r .html)
! grep -q '1234' <<< "$html" || fail "private line shown"
! grep -q 'pack' <<< "$html" || fail "private brief shows its pack"
grep -q '<b>Repos:</b> butler<' <<< "$html" || fail "private repos"

# Anything shaped like a secret is cut.
html=$(card $'Fix the token.\n1. Use ghp_abcdefghijklmnopqrstuvwxyz0123 for it.' | jq -r .html)
! grep -q 'ghp_abc' <<< "$html" || fail "secret shown"
grep -q 'redacted' <<< "$html" || fail "no redaction mark"

# The landed card still renders with the shared style.
jq -n '{data: [{payload: {type: "result", result: "It works.\nChanged: a thing\nBefore: old\nAfter: new\nReady: x\nGo live: soon\nAaron must: nothing\nCommit: jimbo abc123"}}]}' > "$work/events"
jq -n --slurpfile events "$work/events" --rawfile mood "$work/mood" --rawfile css "$dir/card.css" --arg title T \
  -f "$dir/report.jq" | jq -r .html | grep -q '\.hero {' || fail "report card lost its style"

# The notice sends the drawn card, or the mood picture alone when drawing fails, never nothing.
mkdir "$work/bin"
bash=$(command -v bash)
printf '#!%s\n{ cat; echo "FILES: $*"; } > "$NOTICE"\n' "$bash" > "$work/bin/butler-notify"
printf '#!%s\ncat > /dev/null; echo "$CARD_PNG"\n' "$bash" > "$work/bin/render-ok"
printf '#!%s\ncat > /dev/null; exit 1\n' "$bash" > "$work/bin/render-fail"
chmod +x "$work/bin/"*
echo png > "$work/card.png"
jq -n '{request: "Make the start card visual.\n1. Draw it."}' > "$work/request.json"
export PATH="$work/bin:$PATH" NOTICE="$work/notice" CARD_DIR="$dir" MOOD_URI="$work/mood" MOOD_PICTURE=/moods/diligent.webp CARD_PNG="$work/card.png"
RENDER=render-ok bash "$dir/start-notice.sh" "$work/request.json" id1 https://claude.ai/code/session_x butler running
grep -q "^Change started: Make the start card visual.$" "$work/notice" || fail "notice text: $(cat "$work/notice")"
grep -q "FILES: $work/card.png" "$work/notice" || fail "card not attached"
RENDER=render-fail bash "$dir/start-notice.sh" "$work/request.json" id1 https://claude.ai/code/session_x butler running 2> /dev/null
grep -q "FILES: /moods/diligent.webp" "$work/notice" || fail "no fallback picture"
grep -q 'session_x' "$work/notice" || fail "fallback lost the link"
CARD_DIR=/nonexistent RENDER=render-ok bash "$dir/start-notice.sh" "$work/request.json" id1 https://claude.ai/code/session_x butler running 2> /dev/null
grep -q "^Change started: Make the start card visual.$" "$work/notice" || fail "broken card builder lost the notice"
grep -q "FILES: /moods/diligent.webp" "$work/notice" || fail "broken card builder lost the picture"
echo "start and landed cards: ok"
