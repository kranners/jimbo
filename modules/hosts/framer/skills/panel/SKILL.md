---
name: panel
description: Turn the wall panel's screen on or off, or set its brightness, overriding its daily brightness schedule until the next scheduled step.
---

# Panel screen

The panel's backlight follows a daily schedule, and `panel` overrides it until the schedule's next step, when the schedule takes over again.
Run it with Bash.

```sh
panel status            # current brightness, and whether it is overridden until the next step
panel brightness 40     # set brightness to 40%, 0 to 100
panel off               # backlight off
panel on                # back on at the schedule's daytime brightness
panel schedule          # drop the override and follow the schedule now
```

"Dimmer" or "brighter" with no number means reading `panel status` first and moving about 20 points.
The wake word lights the screen for two minutes, then it returns to the level set here, so after `panel off` the screen still lights while Aaron is talking.

## Speaking the answer

Say the new level and, from `panel status`, until when it holds, for example "Screen off until 6 pm."
