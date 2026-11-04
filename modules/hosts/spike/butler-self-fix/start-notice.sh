# DMs Aaron that a change started: the start card, drawn from start.jq with the diligent mood as its banner, over a short text of its title and link.
# When the card cannot be built or drawn it sends the same text with the diligent picture alone, so a start is never lost.
# usage: start-notice.sh <request.json> <id> <link> <pack> <state>
# env: CARD_DIR, holding start.jq and card.css; MOOD_URI, a file of the banner as a data URI; MOOD_PICTURE, the fallback picture; RENDER, which reads HTML on stdin and prints the PNG's path.
set -u
request=$1 id=$2 link=$3 pack=$4 state=$5
card="" title=""
if built=$(jq -n --arg request "$(jq -r .request "$request")" --arg id "$id" --arg pack "$pack" --arg state "$state" \
  --rawfile mood "$MOOD_URI" --rawfile css "$CARD_DIR/card.css" -f "$CARD_DIR/start.jq") && [ -n "$built" ]; then
  title=$(jq -r .title <<< "$built")
  card=$(jq -r .html <<< "$built" | "$RENDER") && [ -s "$card" ] ||
    { echo "Could not render change $id's start card; sending the diligent picture alone" >&2; card=""; }
fi
if [ -z "$title" ]; then
  title=$(jq -r '.request | split("\n") | map(select(test("\\S"))) | first // "" | .[:120]' "$request")
fi
printf 'Change started: %s\n%s\n' "$title" "$link" | butler-notify "${card:-$MOOD_PICTURE}" > /dev/null
