# One calendar's events from Home Assistant's REST API, with the uid and recurrence_id update and delete take.
.[] | {
  calendar: $calendar,
  start: (.start.dateTime // .start.date),
  end: (.end.dateTime // .end.date),
  summary,
  location,
  uid,
  recurrence_id
}
