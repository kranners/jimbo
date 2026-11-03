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
    # The 15-minute load average over the core count.
    loadRatio = 2;
    # Critical memory pressure on Linux: the percent of time fully stalled, or the share of swap used.
    psiCritical = 10;
    swapCritical = 0.9;
    # On battery with keep-awake on.
    batteryWarnPercent = 40;
    batteryActPercent = 20;
    downMinutes = 10;
    claudeWarnPercent = 80;
    claudeActPercent = 95;
    maxRunningChanges = 4;
    maxChangeHours = 3;
    dockerCacheGB = 20;
    maxGenerations = 30;
  };
  # Between start and end only urgent notices go out; the rest wait for a summary at summary.
  quiet = {
    start = "23:00";
    end = "07:00";
    summary = "07:30";
  };
}
