# One event a line: start, end, calendar, summary, location, uid and, for an occurrence of a recurring event, its recurrence_id.
sort_by(.start) | .[] | [.start, .end, .calendar, .summary, (.location // ""), (.uid // ""), (.recurrence_id // "")] | @tsv
