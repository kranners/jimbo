---
name: google-calendar
description: Read and add events on Aaron's Google Calendar through Home Assistant on spike. Use for "what's on today", "am I free Thursday", "put dinner with Sam on Friday at 7".
---

# Google Calendar

Home Assistant on spike holds the Google Calendar connection.
Run `home-assistant-api <METHOD> <path> [json body]` with Bash; it carries the token itself, so never look for or print the token.

## List calendars

```sh
home-assistant-api GET calendars | jq -r '.[] | "\(.entity_id)\t\(.name)"'
```

Google calendars are the `calendar.*` entities whose names match Aaron's Google calendars; the primary one is named after his account.
List them first rather than guessing an entity id.

## Read events

`start` and `end` are ISO 8601 with the local offset, worked out from today's date.

```sh
home-assistant-api GET 'calendars/calendar.ENTITY?start=2026-10-16T00:00:00%2B11:00&end=2026-10-17T00:00:00%2B11:00' \
  | jq -r '.[] | "\(.start.dateTime // .start.date)\t\(.summary)\t\(.location // "")"'
```

Write the offset's `+` as `%2B`.
Ask every relevant calendar, not just the primary one, when asked what is on.

## Add an event

A timed event:

```sh
home-assistant-api POST services/calendar/create_event \
  '{"entity_id":"calendar.ENTITY","summary":"Dinner with Sam","start_date_time":"2026-10-16 19:00:00","end_date_time":"2026-10-16 21:00:00"}'
```

An all-day event uses `start_date` and `end_date` (`YYYY-MM-DD`, end exclusive) instead.
Times without an offset are in Home Assistant's own time zone, which is Aaron's.
When no end is given, make it an hour after the start.
Add to the primary calendar unless Aaron names another.

Read back what was created in one short sentence: the title, the day and the time.
This skill only reads and adds; if Aaron asks to move or cancel an event, say so and point him at his phone.
