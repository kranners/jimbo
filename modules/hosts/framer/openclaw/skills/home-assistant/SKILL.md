---
name: home-assistant
description: Read the home's sensors, weather and calendars, and run Home Assistant services such as lights and media.
---

# Home Assistant

Run `home-assistant-api <METHOD> <path> [json body]` with Bash.
It calls `http://10.100.0.1:8123/api/<path>` with the token itself, so never look for or print the token.

## Read every entity's state

```sh
home-assistant-api GET states
```

Pipe it through `jq` to pick out the entity you need, such as `weather.home`, instead of reading it all aloud.

## Read one entity

```sh
home-assistant-api GET states/weather.home
```

## Run a service

```sh
home-assistant-api POST services/light/turn_on '{"entity_id": "light.kitchen"}'
```

The domain and service come from the entity: `light/turn_off`, `media_player/media_pause`, `switch/toggle`.

## Read a calendar's events

```sh
home-assistant-api GET calendars
home-assistant-api GET 'calendars/calendar.home?start=2026-10-10T00:00:00Z&end=2026-10-11T00:00:00Z'
```

Use ISO 8601 times for `start` and `end`, covering the day asked about.
