# Turns a finished change's final message into the standard report: the summary before it and what Aaron must do as text, and the card as HTML for `render html`, or nothing when the message has no report.
# Its style is card.css, shared with start.jq's card, passed as $css.
# The session ends its message with lines `Changed:`, `Before:`, `After:`, `Ready:`, `Go live:`, `Aaron must:` and `Commit:`, as butler-self-fix's preamble asks.
def labels: ["Changed", "Before", "After", "Ready", "Go live", "Aaron must", "Commit"];
def items: split(";") | map(gsub("^\\s+|\\s+$"; "")) | map(select(length > 0));
def nothing: ascii_downcase | test("^(nothing|none|no)\\b|^n/?a$");

([$events[0].data // [] | .[] | .payload | select(type == "object" and .type == "result")] | first | .result // "")
| split("\n")
| map(gsub("\\*\\*|__|`"; "") | sub("^[\\s>*•\\-#]+"; ""))
| reduce .[] as $line ({prose: []};
    ($line | capture("^(?<k>[A-Za-z ]+?)\\s*:\\s*(?<v>.*)$") // null) as $m
    | if $m and (labels | index($m.k)) then (if $m.v | length > 0 then .[$m.k] = $m.v else . end)
      elif .Changed then .
      else .prose += [$line] end)
| select(.Changed)
| (.Ready // "" | items) as $ready
| (.["Aaron must"] // "nothing" | items) as $must
| ($must | length == 0 or (.[0] | nothing)) as $nothingNeeded
| {
    prose: (.prose | join(" ") | gsub("\\s+"; " ") | gsub("^ | $"; "")),
    todo: (if $nothingNeeded then "" else $must | join("; ") end),
    html: ("<!doctype html><html><head><meta charset=\"utf-8\"><style>\($css)</style></head><body><div class=\"card\">
<div class=\"hero\" style=\"background-image: url('\($mood)')\"><div class=\"band\"><div class=\"kicker\">Change landed</div><h1>\($title | @html)</h1></div></div>
<div class=\"body\">
<h2>What changed</h2><p class=\"changed\">\(.Changed | @html)</p>
\(if .Before and .After then "<div class=\"ba\"><div class=\"side before\"><span class=\"tag\">Before</span>\(.Before | @html)</div><div class=\"arrow\">➜</div><div class=\"side after\"><span class=\"tag\">Now</span>\(.After | @html)</div></div>" else "" end)
\(if ($ready | length) > 0 then "<h2>Ready to use</h2><ul class=\"ready\">\($ready | map("<li>\(@html)</li>") | join(""))</ul>" else "" end)
<h2>To go live</h2>
\(if .["Go live"] then "<p class=\"when\"><b>Deploys:</b> \(.["Go live"] | @html)</p>" else "" end)
\(if $nothingNeeded then "<span class=\"clear\">✓ Nothing needed from you</span>" else "<ul class=\"todo\">\($must | map("<li>\(@html)</li>") | join(""))</ul>" end)
\(if .Commit then "<div class=\"foot\">\(.Commit | @html)</div>" else "" end)
</div></div></body></html>")
  }
