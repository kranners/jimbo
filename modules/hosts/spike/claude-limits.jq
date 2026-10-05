.limits[]
| "{kind=\"\(.kind)\",model=\"\(.scope.model.display_name // "")\"}" as $labels
| "claude_limit_percent\($labels) \(.percent)",
  if .resets_at then
    "claude_limit_resets_at_seconds\($labels) \(.resets_at | sub("\\.[0-9]+"; "") | sub("\\+00:00$"; "Z") | fromdateiso8601)"
  else
    empty
  end
