---
name: now
description: Work out the current date and time in Aaron's time zone before anything that depends on it. Use for "remind me in two hours", "tonight", "tomorrow morning", "is X open now", "how long until", and anything said to happen at a time of day.
---

# Now

Call the `now` tool with no args; it prints the local weekday, date, time, time zone abbreviation and UTC offset in Australia/Melbourne, such as `Tuesday 3 November 2026, 14:05:12 AEDT (UTC+11:00), Australia/Melbourne`.

- Every message from Aaron arrives with the time it was sent beside it, but a turn can run for minutes, so call `now` again right before working out a time.
- Turn relative times into absolute ones from its output, and say the absolute time back, such as "at 4:05 pm today".
- For "is it open now", compare its weekday and time against the place's hours for that day, and mind public holidays.
- Melbourne observes daylight saving, AEDT (UTC+11) from early October to early April and AEST (UTC+10) otherwise, so use the offset `now` prints rather than assuming one.
- Never guess the time from timestamps in other tools' output.
