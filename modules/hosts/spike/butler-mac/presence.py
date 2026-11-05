# Presence notes for mac: who else touched a machine lately and what they were doing, and whether Aaron himself is at it.
# Nothing here locks or refuses anything; it only adds lines to a result, so desk sessions and threads can share a Mac.
# mac.py takes this file in place of its @presence@ line, without the imports, which it already has; test_presence.py
# imports it directly.
import json
import os

# Another thread's use of a machine within this long is mentioned.
PRESENCE_MS = 5 * 60
# Keyboard or mouse input this recent, and not butler's own, means Aaron is at the machine.
AARON_IDLE = 20
# Butler's own input lands up to this long after its command recorded itself, so idle that recent is taken for its own.
OWN_INPUT_SLACK = 4
MACOS_IDLE = "ioreg -c IOHIDSystem -d 4 | awk '/HIDIdleTime/ {print int($NF/1000000000); exit}'"


def presence_file(folder, host):
    return os.path.join(folder, host + '.json')


def presence_load(folder, host):
    try:
        with open(presence_file(folder, host)) as f:
            data = json.load(f)
        return data if isinstance(data, dict) else {}
    except (FileNotFoundError, ValueError):
        return {}


def presence_save(folder, host, data, now):
    os.makedirs(folder, mode=0o700, exist_ok=True)
    data = {k: v for k, v in data.items() if now - v.get('at', 0) <= PRESENCE_MS * 6}
    with open(presence_file(folder, host) + '.new', 'w') as f:
        json.dump(data, f)
    os.replace(presence_file(folder, host) + '.new', presence_file(folder, host))


def presence_who(entry):
    """A desk session by its task, any other thread by its title, the DM as itself."""
    if entry.get('session'):
        return 'Desk session "%s"' % entry['session']
    title = (entry.get('title') or '').strip()
    return 'Thread "%s"' % title if title else 'Another thread'


def presence_where(entry, host):
    app = (entry.get('app') or '').strip()
    window = (entry.get('window') or '').strip()
    if not app:
        return 'was on %s' % host
    return 'is in %s on %s%s' % (app, host, ', %s' % window if window else '')


def presence_lines(data, me, host, now):
    """Lines about every other thread that used host in the last PRESENCE_MS, newest first."""
    lines = []
    for key, entry in sorted(data.items(), key=lambda kv: -kv[1].get('at', 0)):
        if key == me or now - entry.get('at', 0) > PRESENCE_MS:
            continue
        minutes = int((now - entry['at']) // 60)
        when = 'just now' if minutes < 1 else '%d min ago' % minutes
        doing = (' (%s)' % entry['action']) if entry.get('action') else ''
        lines.append('%s %s, %s%s.' % (presence_who(entry), presence_where(entry, host), when, doing))
    return lines[:3]


def aaron_active(idle, last_butler, now):
    """Whether the Mac's own idle time shows Aaron's keyboard or mouse, not butler's input, in the last AARON_IDLE seconds."""
    if idle is None or idle >= AARON_IDLE:
        return False
    return now - idle > last_butler + OWN_INPUT_SLACK


def presence_note(lines, aaron, idle, host):
    """The note added to a mac result, or '' when there is nothing to say."""
    out = []
    if aaron:
        out.append('Aaron is using this Mac right now (his keyboard or mouse, %d s ago): wait, or work in a window he is not in.' % idle
                   if host != 'jimbo' else 'Aaron is using this machine right now: wait, or work in a window he is not in.')
    out.extend(lines)
    if not out:
        return ''
    return '\n[presence on %s, shared context, nothing is locked]\n%s' % (host, '\n'.join(out))


def presence_record(folder, host, me, entry, now):
    """Records this thread's latest look at host, returning everything recorded, its own entry included."""
    data = presence_load(folder, host)
    if me:
        data[me] = dict(entry, at=now)
        presence_save(folder, host, data, now)
    return data


def presence_last_butler(data, now):
    return max([v.get('at', 0) for v in data.values()] + [0])
