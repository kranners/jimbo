"""Keeps Butler's overlay up on Aaron's Mac for as long as any of butler's turns runs, wherever the work happens.

Every POLL seconds it reads the daemon's call state file, whose `work` lists each running turn's start and the name
of the tool it last used, never what the tool was given, and over one kept-open ssh connection per Mac, with
butler's Mac key, runs that Mac's `butler-overlay`: `work` every KEEP seconds while a turn runs, which keeps him on
screen in his working pose, `work <bubble>` when a turn starts or moves to a tool worth narrating, and `rest` once
none runs, which fades him out. A Mac that is asleep or off WireGuard is tried again after BACKOFF seconds.
"""
import json
import os
import subprocess
import sys
import time

CONFIG = json.loads(os.environ['RELAY_CONFIG'])
POLL = 2
KEEP = 10
BACKOFF = 60
# The call state is rewritten every 5 s; older than this, the daemon has stopped, so no turn runs.
STALE = 30
# A narrated bubble at most this often, and the same one not again within REPEAT seconds.
BUBBLE_GAP = 4
REPEAT = 15
PENDING = 10

# What a tool's name says about the step, in a few plain words. `mac` narrates itself on the Mac it drives.
COMMANDS = {
    'shell': 'Running a script on spike', 'mac': None, 'mail': 'Checking the mail', 'mail-send': 'Sending an email',
    'calendar': 'Checking the calendar', 'reminders': 'Checking the reminders', 'home': 'Talking to Home Assistant',
    'life': 'Looking through my records', 'kanban': 'Checking the kanban board', 'maps': 'Looking at the map',
    'weather': 'Checking the weather', 'github-issue': 'Looking at GitHub', 'backlogic-ticket': 'Filing a ticket',
    'change': 'Arranging a change', 'self-fix': 'Arranging a change', 'memory-note': 'Making a note',
    'memory-save': 'Saving my memory', 'render': 'Drawing something up', 'imagine': 'Painting a picture',
    'drive': 'Looking in Google Drive', 'slack': 'Reading Slack', 'inbox': 'Checking the inbox',
    'now': 'Checking the time', 'jobs': 'Scheduling a job', 'monitor': 'Checking the machines',
    'context': 'Catching up on context', 'photos': 'Looking through photos', 'remarkable': 'Reading the reMarkable',
    'garmin': 'Checking Garmin', 'hevy': 'Checking Hevy', 'up': 'Checking the bank', 'notify': 'Messaging you',
    'call-say': 'Messaging you', 'land-queue': 'Checking the landing queue', 'voice-sample': 'Recording voices',
    'messenger-chats': 'Checking Messenger', 'messenger-read': 'Checking Messenger',
    'messenger-send': 'Sending a message', 'chat': 'Reading the chats',
}
TOOLS = {
    'Read': 'Reading', 'Glob': 'Looking for files', 'Grep': 'Searching files', 'Edit': 'Writing notes',
    'Write': 'Writing notes', 'WebSearch': 'Searching the web', 'WebFetch': 'Reading a web page',
}


def narrate(tool):
    """A short bubble for a tool's name, or None for one not worth narrating."""
    if not tool:
        return None
    if tool.startswith('mcp__commands__'):
        name = tool[len('mcp__commands__'):]
        return COMMANDS.get(name, 'Using my %s tool' % name)
    if tool.startswith('mcp__browser__'):
        return 'Using my browser on spike'
    if tool.startswith('mcp__mission__'):
        return 'Planning the work'
    return TOOLS.get(tool)


def read_work(now):
    """Each running turn as (startedAt, tool, toolAt), or [] when none runs or the daemon is not writing."""
    try:
        with open(CONFIG['callState']) as f:
            state = json.load(f)
    except (OSError, ValueError):
        return []
    if now - state.get('updatedAt', 0) / 1000 > STALE:
        return []
    work = state.get('work')
    if isinstance(work, list):
        return [(w.get('startedAt') or 0, w.get('tool'), w.get('toolAt') or 0) for w in work if isinstance(w, dict)]
    # A daemon that predates `work` still counts its running turns.
    running = (state.get('turns') or {}).get('running', 0)
    return [(0, None, 0)] * running if isinstance(running, int) else []


def log(text):
    print(text, flush=True)


class Mac:
    def __init__(self, name, address, user):
        self.name, self.address, self.user = name, address, user
        self.busy = False
        self.sent = 0
        self.retry = 0
        self.down = False
        self.bubble, self.bubbleAt = '', 0
        self.pending, self.pendingAt = None, 0

    def run(self, *words):
        command = ' '.join([CONFIG['overlay']] + ["'%s'" % w.replace("'", "'\\''") for w in words])
        ssh = [
            CONFIG['ssh'], '-i', os.path.join(os.environ['CREDENTIALS_DIRECTORY'], 'butler-mac-key'),
            '-o', 'IdentitiesOnly=yes', '-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=accept-new',
            '-o', 'UserKnownHostsFile=' + os.path.join(CONFIG['state'], 'known_hosts'),
            '-o', 'ConnectTimeout=5', '-o', 'ServerAliveInterval=15', '-o', 'ServerAliveCountMax=2',
            '-o', 'ControlMaster=auto', '-o', 'ControlPersist=10m',
            '-o', 'ControlPath=' + os.path.join(CONFIG['runtime'], self.name),
            '%s@%s' % (self.user, self.address), command,
        ]
        try:
            result = subprocess.run(ssh, stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=12)
            ok, why = result.returncode == 0, (result.stderr.strip().splitlines() or ['exit %d' % result.returncode])[-1]
        except subprocess.TimeoutExpired:
            ok, why = False, 'timed out'
        now = time.time()
        if ok:
            if self.down:
                log('%s: answering again' % self.name)
            self.down = False
            self.sent = now
        else:
            if not self.down:
                log('%s: overlay not reached (%s); trying again every %d s' % (self.name, why[:160], BACKOFF))
            self.down = True
            self.retry = now + BACKOFF
        return ok

    def step(self, now, busy, bubble):
        # The latest bubble waits for the gap after the last one, and is dropped once it is PENDING seconds old.
        if bubble:
            self.pending, self.pendingAt = bubble, now
        if self.down and now < self.retry:
            return
        if busy:
            fresh = self.pending and now - self.pendingAt < PENDING
            if fresh and (self.pending != self.bubble or now - self.bubbleAt > REPEAT) and now - self.bubbleAt >= BUBBLE_GAP:
                bubble, self.pending = self.pending, None
                if self.run('work', bubble):
                    self.busy, self.bubble, self.bubbleAt = True, bubble, now
                    return
            if not self.busy or now - self.sent >= KEEP:
                if self.run('work'):
                    self.busy = True
        elif self.busy and self.run('rest'):
            self.busy, self.bubble, self.pending = False, '', None


def main():
    macs = [Mac(name, host['address'], host['user']) for name, host in CONFIG['hosts'].items()]
    log('showing butler at work on %s' % ', '.join(mac.name for mac in macs))
    seen = {}
    while True:
        now = time.time()
        work = read_work(now)
        bubble = None
        # The newest thing any turn did: a turn starting, or its latest tool.
        events = [(started / 1000, 'Thinking it over') for started, tool, _ in work if started and not tool and started not in seen]
        events += [(at / 1000, narrate(tool)) for started, tool, at in work if tool and seen.get(started) != (tool, at)]
        events = [e for e in events if e[1]]
        if events:
            bubble = max(events)[1]
        seen = {started: (tool, at) for started, tool, at in work}
        for mac in macs:
            mac.step(now, bool(work), bubble)
        time.sleep(POLL)


if __name__ == '__main__':
    sys.exit(main())
