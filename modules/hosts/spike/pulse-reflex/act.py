"""pulse-reflex-act: the one root channel pulse's reflexes act through.

pulse runs unprivileged and never holds root: a reflex drops a request, one JSON file, into the spool's requests/,
and this program, run as root by pulse-reflex-act.path whenever that folder is not empty, does the one fixed action
the request names, only on a target its allowlist names, and writes the result to results/<id>.json.
Nothing in a request is ever run: it names an action from ACTIONS and a target, both checked against CONFIG, which
jimbo writes into the store.
"""
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import time

CONFIG = {}
ID = re.compile(r'[a-z0-9][a-z0-9-]{0,63}')
MAX_REQUEST = 4096
SETTLING = ('activating', 'deactivating', 'reloading')
# The substates of a unit actually starting, as against one waiting out its RestartSec in auto-restart.
STARTING = ('start', 'start-pre', 'start-post', 'condition')


class Refused(Exception):
    """A request this channel will not carry out; the result says why."""


def systemctl(*args, timeout=60):
    return subprocess.run([CONFIG['systemctl'], *args], capture_output=True, text=True, timeout=timeout)


def show(unit):
    out = systemctl('show', unit, '-p', 'LoadState', '-p', 'ActiveState', '-p', 'SubState', '-p', 'Result',
                    '-p', 'InactiveExitTimestampMonotonic', '-p', 'TriggeredBy', '--no-pager').stdout
    props = {}
    for line in out.splitlines():
        key, _, value = line.partition('=')
        props[key] = value
    return props


def uptime_us():
    # systemd's *TimestampMonotonic are CLOCK_MONOTONIC, which time.monotonic reads on Linux.
    return int(time.monotonic() * 1_000_000)


def wait_settled(unit, timeout):
    deadline = time.monotonic() + timeout
    props = show(unit)
    while props.get('ActiveState') in SETTLING and time.monotonic() < deadline:
        time.sleep(2)
        props = show(unit)
    return props


def state_text(props):
    return '%s (%s)' % (props.get('ActiveState', 'unknown'), props.get('Result') or props.get('SubState') or '?')


def protected(unit):
    return any(re.fullmatch(p, unit) for p in CONFIG['protect'])


def allowed(kind, unit):
    if protected(unit):
        raise Refused('%s is protected: nothing automatic touches it' % unit)
    if not any(re.fullmatch(p, unit) for p in CONFIG['units'][kind]):
        raise Refused('%s is not on the %s allowlist' % (unit, kind))
    props = show(unit)
    if props.get('LoadState') != 'loaded':
        raise Refused('%s is not a loaded unit' % unit)
    return props


def start_failed(unit, _request):
    """reset-failed and start a failed unit once."""
    props = allowed('start', unit)
    if props.get('ActiveState') != 'failed':
        raise Refused('%s is %s, not failed' % (unit, state_text(props)))
    systemctl('reset-failed', unit)
    started = systemctl('start', '--no-block', unit)
    if started.returncode != 0:
        raise RuntimeError(started.stderr.strip()[-160:] or 'systemctl start failed')
    return state_text(props), state_text(wait_settled(unit, CONFIG['settleSeconds']))


def restart_stuck(unit, _request):
    """restart a unit that has sat activating past stuckSeconds."""
    props = allowed('restart', unit)
    if props.get('ActiveState') != 'activating' or props.get('SubState') not in STARTING:
        raise Refused('%s is %s %s, not stuck starting' % (unit, props.get('ActiveState'), props.get('SubState')))
    since = int(props.get('InactiveExitTimestampMonotonic') or 0)
    held = (uptime_us() - since) / 1_000_000 if since else 0
    if held < CONFIG['stuckSeconds']:
        raise Refused('%s has been activating %ds, under %ds' % (unit, held, CONFIG['stuckSeconds']))
    restarted = systemctl('restart', '--no-block', unit)
    if restarted.returncode != 0:
        raise RuntimeError(restarted.stderr.strip()[-160:] or 'systemctl restart failed')
    return 'activating for %dm' % (held // 60), state_text(wait_settled(unit, CONFIG['settleSeconds']))


def retry_timer(unit, _request):
    """start once the service a timer runs, after its last run failed."""
    props = allowed('timer', unit)
    if '.timer' not in props.get('TriggeredBy', ''):
        raise Refused('%s is not run by a timer' % unit)
    return start_failed_any(unit, props)


def start_failed_any(unit, props):
    if props.get('ActiveState') != 'failed' and props.get('Result') in ('success', ''):
        raise Refused('%s is %s: its last run did not fail' % (unit, state_text(props)))
    if props.get('ActiveState') in SETTLING or props.get('ActiveState') == 'active':
        raise Refused('%s is %s already' % (unit, state_text(props)))
    systemctl('reset-failed', unit)
    started = systemctl('start', '--no-block', unit)
    if started.returncode != 0:
        raise RuntimeError(started.stderr.strip()[-160:] or 'systemctl start failed')
    return state_text(props), state_text(wait_settled(unit, CONFIG['settleSeconds']))


def start_unit(unit, _request):
    """start an idle oneshot now, such as the board's safe-prompts sweep."""
    props = allowed('run', unit)
    if props.get('ActiveState') in SETTLING or props.get('ActiveState') == 'active':
        raise Refused('%s is %s already' % (unit, state_text(props)))
    started = systemctl('start', '--no-block', unit)
    if started.returncode != 0:
        raise RuntimeError(started.stderr.strip()[-160:] or 'systemctl start failed')
    return state_text(props), state_text(wait_settled(unit, CONFIG['settleSeconds']))


def unblock_state_file(path, _request):
    """give a read-only state file its owner's write bit back, then start its failed unit once; never deletes it."""
    unit = CONFIG['stateFiles'].get(path)
    if unit is None:
        raise Refused('%s is not a state file this channel may unblock' % path)
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    except FileNotFoundError:
        raise Refused('%s does not exist' % path)
    except OSError as error:
        raise Refused('%s cannot be opened safely: %s' % (path, error.strerror))
    try:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode):
            raise Refused('%s is not a regular file' % path)
        if info.st_uid == 0:
            raise Refused('%s is owned by root' % path)
        if info.st_nlink != 1 or info.st_uid != os.stat(os.path.dirname(path)).st_uid:
            raise Refused('%s is a hard link or not owned by its folder\'s owner' % path)
        if info.st_mode & stat.S_IWUSR:
            raise Refused('%s is already writable by its owner' % path)
        before = oct(stat.S_IMODE(info.st_mode))
        os.fchmod(fd, stat.S_IMODE(info.st_mode) | stat.S_IWUSR)
        after = oct(stat.S_IMODE(os.fstat(fd).st_mode))
    finally:
        os.close(fd)
    props = show(unit)
    unit_line = ''
    if props.get('ActiveState') == 'failed':
        systemctl('reset-failed', unit)
        systemctl('start', '--no-block', unit)
        unit_line = ', %s %s' % (unit, state_text(wait_settled(unit, CONFIG['settleSeconds'])))
    return 'mode %s' % before, 'mode %s%s' % (after, unit_line)


def mac_free_disk(host, _request):
    """the fixed caches-only clean-up on a Mac under its free-disk floor, over ssh with butler's Mac key."""
    mac = CONFIG['macs'].get(host)
    if mac is None:
        raise Refused('%s is not a machine this channel may clean' % host)
    key = os.path.join(os.environ.get('CREDENTIALS_DIRECTORY', ''), 'butler-mac-key')
    args = [CONFIG['ssh'], '-i', key, '-o', 'IdentitiesOnly=yes', '-o', 'BatchMode=yes',
            '-o', 'StrictHostKeyChecking=yes', '-o', 'UserKnownHostsFile=' + CONFIG['knownHosts'],
            '-o', 'ConnectTimeout=8', '-o', 'ControlMaster=no', '-o', 'ControlPath=none',
            '%s@%s' % (mac['user'], mac['address']), 'bash -s']
    script = CONFIG['macScript'].replace('@floor@', str(CONFIG['macFreeFloor']))
    try:
        result = subprocess.run(args, input=script, capture_output=True, text=True, timeout=CONFIG['macTimeout'])
    except subprocess.TimeoutExpired:
        raise RuntimeError('%s did not finish within %ds' % (host, CONFIG['macTimeout']))
    lines = dict(line.split(' ', 1) for line in result.stdout.splitlines() if ' ' in line)
    if 'skip' in lines:
        raise Refused('%s has %s free, over its floor' % (host, lines['skip']))
    if result.returncode != 0 or 'after' not in lines:
        raise RuntimeError((result.stderr.strip().splitlines() or ['exit %d' % result.returncode])[-1][:160])
    return lines.get('before', '?') + ' free', lines['after'] + ' free'


ACTIONS = {
    'start-failed': start_failed,
    'restart-stuck': restart_stuck,
    'retry-timer': retry_timer,
    'start-unit': start_unit,
    'unblock-state-file': unblock_state_file,
    'mac-free-disk': mac_free_disk,
}


def read_small(path):
    """A small regular file's text, never following a link or blocking on a FIFO; None when there is none."""
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    except OSError:
        return None
    try:
        if not stat.S_ISREG(os.fstat(fd).st_mode):
            return 'not a file'
        return os.read(fd, 256).decode(errors='replace')
    finally:
        os.close(fd)


def kill_switch():
    """Why nothing may run now, or None."""
    if os.path.lexists(os.path.join(CONFIG['spool'], 'off')):
        return 'reflexes are off (pulse reflex off)'
    mode = read_small(CONFIG['monitorMode'])
    if mode is not None and mode.strip() == 'off':
        return 'acting is off (monitor act off)'
    return None


def load_state():
    try:
        with open(os.path.join(CONFIG['state'], 'state.json')) as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def save_state(state):
    path = os.path.join(CONFIG['state'], 'state.json')
    with open(path + '.tmp', 'w') as f:
        json.dump(state, f)
    os.replace(path + '.tmp', path)


def rate_limited(state, key, now):
    """This channel's own ceilings, under whatever pulse decides: perTargetPerHour actions of any kind on one target,
    and perHour in all."""
    runs = [t for t in state.get(key, []) if now - t < 3600]
    state[key] = runs
    if len(runs) >= CONFIG['perTargetPerHour']:
        raise Refused('%s was acted on %d times in the last hour' % (key, len(runs)))
    every = [t for t in state.get('*', []) if now - t < 3600]
    state['*'] = every
    if len(every) >= CONFIG['perHour']:
        raise Refused('%d actions in the last hour, the most this channel takes' % len(every))
    runs.append(now)
    every.append(now)


def read_request(path):
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    try:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode) or info.st_size > MAX_REQUEST:
            raise Refused('not a small regular file')
        data = os.read(fd, MAX_REQUEST + 1)
    finally:
        os.close(fd)
    request = json.loads(data)
    if not isinstance(request, dict) or not isinstance(request.get('action'), str) or not isinstance(request.get('target'), str):
        raise Refused('a request names an action and a target')
    return request


def write_result(rid, result):
    folder = os.path.join(CONFIG['spool'], 'results')
    path = os.path.join(folder, rid + '.json')
    tmp = os.path.join(folder, '.' + rid + '.tmp')
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NOFOLLOW, 0o640)
    with os.fdopen(fd, 'w') as f:
        json.dump(result, f)
    os.replace(tmp, path)


def handle(name, state, now):
    rid = name[:-5]
    path = os.path.join(CONFIG['spool'], 'requests', name)
    result = {'id': rid, 'at': int(now)}
    try:
        try:
            request = read_request(path)
        finally:
            try:
                os.unlink(path)
            except OSError:
                pass
        result.update(action=request['action'], target=request['target'])
        action = ACTIONS.get(request['action'])
        if action is None:
            raise Refused('%s is not an action this channel knows' % request['action'])
        if len(request['target']) > 200:
            raise Refused('the target is too long')
        why = kill_switch()
        if why:
            raise Refused(why)
        key = 'target:' + request['target']
        rate_limited(state, key, now)
        save_state(state)
        try:
            before, after = action(request['target'], request)
        except Refused:
            # Only an action actually taken counts against the ceilings.
            state[key].pop()
            state['*'].pop()
            save_state(state)
            raise
        result.update(result='done', before=before, after=after)
    except Refused as why:
        result.update(result='refused', reason=str(why)[:240])
    except (ValueError, KeyError, OSError) as error:
        result.update(result='refused', reason=('a malformed request: %s' % error)[:240])
    except Exception as error:  # noqa: BLE001
        result.update(result='failed', reason=str(error)[:240])
    print(json.dumps(result), flush=True)
    write_result(rid, result)
    return result


def prune_results(now):
    folder = os.path.join(CONFIG['spool'], 'results')
    for name in os.listdir(folder):
        path = os.path.join(folder, name)
        try:
            if now - os.lstat(path).st_mtime > 3600:
                os.unlink(path)
        except OSError:
            pass


def remove(path):
    """Removes anything that is not a request, a folder included, never following a link, so the path unit's
    DirectoryNotEmpty never stays true."""
    try:
        if stat.S_ISDIR(os.lstat(path).st_mode):
            shutil.rmtree(path, ignore_errors=True)
        else:
            os.unlink(path)
    except OSError:
        pass


def per_minute(state, now):
    """At most perMinute requests are answered a minute; the rest are dropped unanswered, so a flood fills nothing."""
    recent = [t for t in state.get('handled', []) if now - t < 60]
    state['handled'] = recent
    if len(recent) >= CONFIG['perMinute']:
        return False
    recent.append(now)
    return True


def run():
    folder = os.path.join(CONFIG['spool'], 'requests')
    state = load_state()
    # Loop until the folder is empty, so a burst of requests is one run; whatever cannot be read is removed.
    for _ in range(200):
        entries = os.listdir(folder)
        if not entries:
            break
        for name in sorted(entries):
            path = os.path.join(folder, name)
            if not (name.endswith('.json') and ID.fullmatch(name[:-5])):
                remove(path)
            elif per_minute(state, time.time()):
                handle(name, state, time.time())
            else:
                print(json.dumps({'id': name[:-5], 'result': 'dropped', 'reason': 'over the per-minute cap'}), flush=True)
                remove(path)
    for name in os.listdir(folder):
        remove(os.path.join(folder, name))
    save_state(state)
    prune_results(time.time())
    return 0


def main(argv):
    with open(os.environ['PULSE_REFLEX_ACT_CONFIG']) as f:
        CONFIG.update(json.load(f))
    return run()


if __name__ == '__main__':
    sys.exit(main(sys.argv))
