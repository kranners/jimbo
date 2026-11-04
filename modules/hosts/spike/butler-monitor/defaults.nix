# The machines monitor's limits, in one place: butler-monitor.nix's defaults and its flake check both read them.
{
  thresholds = {
    # Free disk: under either warns, under either acts.
    diskWarnRatio = 0.15;
    diskWarnGB = 20;
    diskActRatio = 0.08;
    diskActGB = 10;
    # Free memory: warns at once, acts once it has lasted memActMinutes.
    memWarnRatio = 0.15;
    memActRatio = 0.08;
    memActMinutes = 5;
    # The 15-minute load average over the core count: over loadNoteRatio is only logged, and only over loadRatio for
    # loadMinutes is it news, since Aaron's own parallel sessions saturate pilot as a matter of course.
    loadNoteRatio = 2;
    loadRatio = 4;
    loadMinutes = 30;
    # Critical memory pressure on Linux: the percent of time fully stalled, or the share of swap used.
    psiCritical = 10;
    swapCritical = 0.9;
    # Critical pressure is told only once it has lasted this long, unless the monitor acted on it first.
    pressureMinutes = 10;
    # A service in overLimitRestart over its memory limit under critical pressure is restarted at most this often.
    overLimitRestartMinutes = 30;
    # On battery with keep-awake on.
    batteryWarnPercent = 40;
    batteryActPercent = 20;
    downMinutes = 10;
    claudeWarnPercent = 80;
    claudeActPercent = 95;
    # butler runs at most 2 turns at once while any account is at this share of its session or week.
    claudeBackoffPercent = 90;
    # butler's turn pool: a turn waiting this long for a slot, or every slot busy this long, warns once.
    turnQueueWarnSeconds = 120;
    turnSlotsBusyMinutes = 15;
    # A turn that has waited this long is stuck, not just queued, and is the only turn finding Aaron is told.
    turnStuckMinutes = 30;
    maxRunningChanges = 4;
    maxChangeHours = 3;
    dockerCacheGB = 20;
    # A failed unit on spike is told only once it fails this many runs in a row (failStreaks may set its own), stays
    # failed this long, or fails this often in a day, about once an hour, since butler-builders alone self-heals a
    # handful of failed pushes a day; anything less, such as one run that the next run fixed, is only
    # logged with its cause.
    unitFailRuns = 3;
    unitFailedMinutes = 10;
    unitFailsPerDay = 24;
    # Prometheus not answering is told only once it has lasted this long.
    unknownMinutes = 30;
    # A problem must be gone this long before it counts as resolved, so one at a threshold's edge is not told twice.
    clearMinutes = 30;
    # A problem Aaron was told about is told again, once, as still open after this long.
    stillOpenHours = 24;
    # butler-monitor.nix sets it from jimbo.keepGenerations.
    maxGenerations = 5;
  };
  # Between start and end only urgent notices go out; the rest wait for one short summary at summary, sent only when
  # something was held or done overnight.
  quiet = {
    start = "23:00";
    end = "07:00";
    summary = "07:30";
  };
}
