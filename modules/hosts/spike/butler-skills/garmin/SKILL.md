---
name: garmin
description: Read Aaron's Garmin health data, such as sleep, HRV, Body Battery, stress, steps, resting heart rate and activities. Use for "how did I sleep", "what's my HRV doing", "how many steps this week", "what was my last run".
---

# Garmin

Use the `garmin` tool, passing the words after `garmin` as `args`, such as `["sleep", "yesterday"]`.
It reads Garmin Connect's official Personal API and prints compact JSON holding only numbers, dates and enum codes such as `BALANCED` or `HRV_UNBALANCED_2`, so it never carries text anyone else wrote.

- `garmin summary [day]` is the day's summary: resting heart rate, steps, average stress, and Body Battery's high and low.
- `garmin sleep [day]` is the night ending that morning: sleep score, time in each stage, and overnight HRV and resting heart rate.
- `garmin sleep-range [from [to]]` gives one sleep summary per night.
- `garmin hrv [day]` is that night's HRV summary against Aaron's baseline, with its status.
- `garmin hrv-range [from [to]]` gives one HRV summary per night, for the trend.
- `garmin body-battery [from [to]]` gives each day's Body Battery charged and drained.
- `garmin stress [from [to]]` and `garmin steps [from [to]]` give one entry per day.
- `garmin activities [count]` lists the newest activities, 10 unless given, at most 50, by type, start, duration, distance and heart rate, without their names.
- `garmin activity <id>` gives one activity's details, its id taken from `activities`.
- `garmin profile` gives profile settings such as weight, height and VO2max where Garmin reports them.

A day is `YYYY-MM-DD`, `today` or `yesterday`, today unless given, and a range is the last 7 days unless given.
No arg may start with `-`.
Work out dates from today's date, and Garmin files a night's sleep under the morning it ended.

## Writing about health data

- Answer with the few numbers that matter, rounded, in plain words: "7 h 12 min, score 81, HRV 58 ms and balanced".
- Turn seconds into hours and minutes, and enum codes into plain words.
- Compare with the last week or Aaron's baseline when that answers the question better than one number.
- This is consumer wearable data, not a diagnosis; never give medical advice, and suggest a doctor for anything that worries Aaron.
- Training readiness, training status and recovery time are not in the Personal API, so say so rather than guessing them.

When a call fails saying Garmin refused the Personal API key, tell Aaron in one line that the key has expired or was revoked and he needs to make a new one in Garmin Connect's settings and put it in `/var/lib/secrets/butler-garmin-api-key` on spike, then carry on without Garmin.
