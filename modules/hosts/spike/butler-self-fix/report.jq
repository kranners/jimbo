# Turns a finished self-fix's final message into the standard report: the summary before it and what Aaron must do as text, and the card as HTML for `render html`, or nothing when the message has no report.
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
    html: ("<!doctype html><html><head><meta charset=\"utf-8\"><style>
body { margin: 0; background: #f6f1e4; color: #2b2418; font-family: Georgia, \"DejaVu Serif\", serif; }
.card { margin: 0; }
.hero { position: relative; height: 300px; background: #1a7a82 center 38% / cover no-repeat; }
.hero .band { position: absolute; left: 0; right: 0; bottom: 0; padding: 40px 28px 16px; background: linear-gradient(rgba(20,16,8,0), rgba(20,16,8,.6) 30%, rgba(20,16,8,.88)); color: #fbf3dc; }
.hero .kicker { font: 600 15px/1 system-ui, sans-serif; letter-spacing: .18em; text-transform: uppercase; color: #e8c462; }
.hero h1 { margin: 8px 0 0; font-size: 30px; line-height: 1.2; }
.body { padding: 22px 28px 26px; }
h2 { margin: 22px 0 10px; font: 700 14px/1 system-ui, sans-serif; letter-spacing: .14em; text-transform: uppercase; color: #8a6418; }
h2:first-child { margin-top: 0; }
.changed { font-size: 22px; line-height: 1.4; margin: 0; }
.ba { display: grid; grid-template-columns: 1fr 44px 1fr; align-items: stretch; margin-top: 18px; }
.ba .side { border-radius: 12px; padding: 14px 16px; font: 17px/1.4 system-ui, sans-serif; }
.ba .before { background: #efe2cf; border: 2px solid #c9a98a; color: #5a4632; }
.ba .after { background: #dcefeb; border: 2px solid #1a7a82; color: #0f4d52; }
.ba .tag { display: block; font: 700 12px/1 system-ui, sans-serif; letter-spacing: .14em; text-transform: uppercase; margin-bottom: 8px; opacity: .8; }
.ba .arrow { display: flex; align-items: center; justify-content: center; font-size: 30px; color: #8a6418; }
ul { list-style: none; margin: 0; padding: 0; }
li { position: relative; padding: 8px 0 8px 40px; font: 18px/1.4 system-ui, sans-serif; border-bottom: 1px solid #e6dcc6; }
li:last-child { border-bottom: 0; }
li::before { position: absolute; left: 4px; top: 7px; width: 24px; height: 24px; border-radius: 6px; font: 700 16px/24px system-ui, sans-serif; text-align: center; }
.ready li::before { content: \"✓\"; background: #1a7a82; color: #fbf3dc; }
.todo li::before { content: \"\"; border: 2.5px solid #b5651d; background: #fff8ec; width: 19px; height: 19px; }
.todo li { color: #6b3a0c; font-weight: 600; }
.clear { display: inline-block; padding: 8px 14px; border-radius: 999px; background: #1a7a82; color: #fbf3dc; font: 600 17px/1.2 system-ui, sans-serif; }
.when { font: 17px/1.4 system-ui, sans-serif; margin: 0 0 10px; }
.when b { color: #8a6418; }
.foot { margin-top: 22px; padding-top: 12px; border-top: 1px solid #d8c9a8; font: 14px/1.3 ui-monospace, \"DejaVu Sans Mono\", monospace; color: #7a6a4e; }
</style></head><body><div class=\"card\">
<div class=\"hero\" style=\"background-image: url('\($mood)')\"><div class=\"band\"><div class=\"kicker\">Self-fix landed</div><h1>\($title | @html)</h1></div></div>
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
