# Turns a change's brief, as it starts, into the start card: its title for the DM's text and the card as HTML for `render html`.
# Its style is card.css, shared with report.jq's landed card, passed as $css, with $mood the banner picture as a data URI.
# A brief that looks private, health, money or messages, shows only its title and repositories, and anything shaped like a secret is cut everywhere.
def redact: gsub("(?<k>(sk|xox[a-z]|gh[pousr]|github_pat|AKIA|eyJ)[-_A-Za-z0-9.]{12,})"; "[redacted]") | gsub("\\b[A-Za-z0-9+/_-]{32,}={0,2}"; "[redacted]");
def plain: gsub("\\*\\*|__|`"; "") | gsub("\\s+"; " ") | gsub("^ | $"; "");
def clip($n): if length > $n then .[:$n] | sub("\\s+\\S*$"; "") + "…" else . end;
def sentence: (capture("^(?<s>.+?[.!?])(\\s|$)").s // .);

($request | split("\n") | map(plain) | map(select(length > 0))) as $lines
| ($lines[0] // "Untitled change"
   | sub("^(From )?Aaron('s request)?\\s*(\\([^)]*\\))?\\s*(,[^:]*)?:\\s*"; "")
   | gsub("^[\"'“‘]+|[\"'”’]+$"; "") | sentence | sub("[\"'”’]+(?<p>[.!?]?)$"; "\(.p)") | redact | clip(90) | (.[:1] | ascii_upcase) + .[1:]) as $title
| ($request | ascii_downcase) as $low
| ([$low | scan("kranners/([a-z0-9._-]+)") | .[0]]
   + [ "claude-discord-threads", "butler-memory", "kanban", "backlogic", "bowerbird", "chromium-claude-profiles"
       | select(. as $r | $low | contains($r)) ]
   + (if $low | test("\\bjimbo\\b") then ["jimbo"] else [] end)
   | map(sub("\\.+$"; "") | sub("\\.git$"; "")) | unique) as $repos
| ($low | test("\\b(health|medical|doctor|diagnos\\w*|medication|symptoms?|bank|salary|debts?|loans?|payments?|invoices?|balances?|transactions?|texts? messages?|imessage|sms)\\b")) as $private
| ($low | test("\\b(approv\\w*|permissions?|access|sandbox|secrets?|credentials?|grants?|auth\\w*|firewall|expose\\w*)\\b")
   and ($low | test("not an? (approvals?|access|permissions?) change") | not)) as $approval
| ([$lines[] | select(test("^\\d+[.)]\\s")) | sub("^\\d+[.)]\\s*"; "")]
   | if length > 0 then . else $lines[1:] end
   | map(sentence | redact | clip(140)) | .[:5]) as $steps
| {
    title: $title,
    html: ("<!doctype html><html><head><meta charset=\"utf-8\"><style>\($css)</style></head><body><div class=\"card\">
<div class=\"hero\" style=\"background-image: url('\($mood)')\"><div class=\"band\"><div class=\"kicker\">Change started</div><h1>\($title | @html)</h1></div></div>
<div class=\"body\">
\(if $private or ($steps | length) == 0 then "" else "<h2>What it will do</h2><ul class=\"steps\">\($steps | map("<li>\(@html)</li>") | join(""))</ul>" end)
<h2>Details</h2><div class=\"facts\">
<div><b>Repos:</b> \(if ($repos | length) > 0 then $repos | join(", ") | @html else "the session picks" end)</div>
\(if $private then "" else "<div><b>Context:</b> \(if $pack == "" then "none" else "the \($pack) pack" end | @html)</div>" end)
<div><b>State:</b> \($state | @html)</div>
</div>
<h2>Before it lands</h2>
\(if $approval then "<span class=\"ask\">Touches access or approvals, so it may ask your yes first</span>" else "<span class=\"clear\">✓ Lands by itself, nothing needed from you</span>" end)
<div class=\"foot\">\($id | @html)</div>
</div></div></body></html>")
  }
