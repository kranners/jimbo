"""Fixture tests for butler-monitor: thresholds, holds, suppression, expected-off marks, escalation, quiet hours and action choice, on fake machines."""

import importlib.util
import json
import os
import sys
import tempfile
import time

# Melbourne time without tzdata, which the build sandbox lacks, so the 4 Nov evidence reads as it did on spike.
os.environ['TZ'] = 'AEST-10AEDT,M10.1.0,M4.1.0/3'
time.tzset()

spec = importlib.util.spec_from_file_location('monitor', sys.argv[1])
monitor = importlib.util.module_from_spec(spec)
spec.loader.exec_module(monitor)

with open(sys.argv[2]) as f:
    monitor.CONFIG.update(json.load(f))
tmp = tempfile.mkdtemp()
monitor.CONFIG.update(state=tmp, holdFile=os.path.join(tmp, 'hold'), group=None, expected=os.path.join(tmp, 'expected'),
                      hosts={'pilot': {}, 'piggys-MBP': {}, 'jimbo': {}})

GB = monitor.GB
DAY = 86400
failures = []


def check(name, condition):
    print(('ok   ' if condition else 'FAIL ') + name)
    if not condition:
        failures.append(name)


def healthy(**over):
    m = {'up': True, 'os': 'macos', 'cores': 8, 'load15': 4, 'load_ratio': 0.5, 'mem_free_ratio': 0.46,
         'disk_free_bytes': 70 * GB, 'disk_total_bytes': 460 * GB, 'pressure': 'normal',
         'on_battery': False, 'battery': 100, 'locked': 'no', 'keepawake': 'on'}
    m.update(over)
    return m


def snap(machines, claude=None, work=None, turns=None):
    return {'machines': machines, 'claude': claude or {}, 'work': work, 'turns': turns}


def judge(machines, state=None, now=1000 * DAY, expected=None, mode=None, **kw):
    state = {} if state is None else state
    snapshot = snap(machines, **kw)
    snapshot['mode'] = mode
    return monitor.settle(monitor.evaluate(snapshot, state, now, expected), state, now)


def levels(findings):
    """The findings Aaron could be told about; info ones are only logged."""
    return {f['key']: f['level'] for f in findings if f['level'] != 'info'}


def noted(findings):
    return {f['key'] for f in findings if f['level'] == 'info'}


local_day = time.struct_time((2026, 11, 4, 14, 0, 0, 2, 308, 1))
local_night = time.struct_time((2026, 11, 4, 2, 0, 0, 2, 308, 1))
local_morning = time.struct_time((2026, 11, 4, 7, 35, 0, 2, 308, 1))

# The machines as Butler measured them by hand on 3 Nov raise nothing.
baseline = {
    'piggys-MBP': healthy(on_battery=True, battery=100),
    'pilot': healthy(mem_free_ratio=0.89, load15=5, load_ratio=5 / 10, cores=10, disk_free_bytes=893 * GB, disk_total_bytes=994 * GB, keepawake='off'),
    'jimbo': healthy(os='windows', mem_free_ratio=3.9 / 16, disk_free_bytes=23.9 * GB, disk_total_bytes=250 * GB, on_battery=None, keepawake='on'),
    'spike': healthy(os='linux', disk_free_bytes=120 * GB, disk_total_bytes=233 * GB, failed_units=[], on_battery=None, keepawake=None),
}
found = levels(judge(baseline, claude={'personal': 20, 'work': 65}))
check('baseline: only jimbo\'s C: drive, 23.9 GB free, warns', found == {'jimbo:disk': 'warn'})

# Disk: under 15% or 20 GB warns, under 8% or 10 GB acts.
check('disk 18 GB of 100 warns', levels(judge({'a': healthy(disk_free_bytes=18 * GB, disk_total_bytes=100 * GB)})) == {'a:disk': 'warn'})
check('disk 9 GB acts', levels(judge({'a': healthy(disk_free_bytes=9 * GB)})) == {'a:disk': 'act'})
check('disk 7% of 1 TB acts', levels(judge({'a': healthy(disk_free_bytes=70 * GB, disk_total_bytes=1000 * GB)})) == {'a:disk': 'act'})

# Memory: under 15% warns at once; under 8% acts only after 5 minutes.
state = {}
lin = {'os': 'linux'}
check('memory 6% warns at first', levels(judge({'a': healthy(mem_free_ratio=0.06, **lin)}, state, now=0)) == {'a:memory': 'warn'})
check('memory 6% still warn after 4 min', levels(judge({'a': healthy(mem_free_ratio=0.06, **lin)}, state, now=240)) == {'a:memory': 'warn'})
check('memory 6% acts after 5 min', levels(judge({'a': healthy(mem_free_ratio=0.06, **lin)}, state, now=300)) == {'a:memory': 'act'})
check('memory hold resets once it recovers', levels(judge({'a': healthy(**lin)}, state, now=360)) == {} and
      levels(judge({'a': healthy(mem_free_ratio=0.06, **lin)}, state, now=420)) == {'a:memory': 'warn'})

check('critical pressure acts', levels(judge({'a': healthy(pressure='critical')})) == {'a:pressure': 'act'})
check('load 2.5x cores is only noted', levels(judge({'a': healthy(load15=20, load_ratio=2.5)})) == {} and
      noted(judge({'a': healthy(load15=20, load_ratio=2.5)})) == {'a:load'})
# pilot at 11:27 on 4 Nov: 39.7 on 18 cores, from Aaron's own board sessions, is not news.
check("pilot's 39.7 on 18 cores is only noted", levels(judge({'pilot': healthy(load15=39.7, load_ratio=39.7 / 18, cores=18)})) == {})
state = {}
check('load over 4x cores is quiet at first', levels(judge({'a': healthy(load15=40, load_ratio=5)}, state, now=0)) == {})
check('load over 4x cores still quiet after 29 minutes', levels(judge({'a': healthy(load15=40, load_ratio=5)}, state, now=29 * 60)) == {})
check('load over 4x cores warns after 30 minutes', levels(judge({'a': healthy(load15=40, load_ratio=5)}, state, now=30 * 60)) == {'a:load': 'warn'})
check('a Mac with little free memory but no pressure is only noted', levels(judge({'a': healthy(mem_free_ratio=0.05)})) == {})

# Battery counts only on battery with keep-awake on.
check('battery 35% warns', levels(judge({'a': healthy(on_battery=True, battery=35)})) == {'a:battery': 'warn'})
check('battery 15% acts', levels(judge({'a': healthy(on_battery=True, battery=15)})) == {'a:battery': 'act'})
check('battery 15% with keep-awake off is fine', levels(judge({'a': healthy(on_battery=True, battery=15, keepawake='off')})) == {})
check('locked with keep-awake on warns', levels(judge({'a': healthy(locked='yes')})) == {'a:locked': 'warn'})
why = judge({'a': healthy(locked='yes', lock_at='01:56', lock_cause='the display went to sleep after 30 minutes idle and the lock followed it')})
check('a lock warning says why', 'at 01:56, and the display went to sleep' in why[0]['text'])
locks = monitor.choose_actions(judge({'piggys-MBP': healthy(locked='yes'), 'pilot': healthy(locked='yes')}), snap({}))
check('a locked piggys-MBP alone gets keep-awake reasserted', [h for a, h in locks if a == 'keepawake-reassert'] == ['piggys-MBP'])
check('keep-awake off on piggys-MBP acts', levels(judge({'piggys-MBP': healthy(keepawake='off')})) == {'piggys-MBP:keepawake': 'act'})
check('keep-awake off on pilot is its default', levels(judge({'pilot': healthy(keepawake='off')})) == {})

# Down: framer urgent at 10 minutes, told once; a laptop or the PC down is only noted, however long.
state = {}
down = {'up': False, 'why': 'does not answer on ssh'}
judge({'pilot': down, 'framer': down, 'jimbo': down}, state, now=0)
f = judge({'pilot': down, 'framer': down, 'jimbo': down}, state, now=600)
check('framer down for 10 minutes acts, the laptop and PC are only noted', levels(f) == {'framer:down': 'act'} and noted(f) == {'pilot:down', 'jimbo:down'})
lines, shout, log = monitor.notices(f, [], state, 600, local_day, {'pilot', 'framer', 'jimbo'})
check('framer down is told once and shouted', len(lines) == 1 and 'framer' in lines[0] and shout and 'framer' in shout)
check('the laptop and PC being down is logged as not told', {e['key'] for e in log if e['route'] == 'kept'} == {'pilot:down', 'jimbo:down'})
told_count = 0
for hour in range(1, 24):
    f = judge({'pilot': down, 'framer': down, 'jimbo': down}, state, now=600 + hour * 3600)
    lines, shout, log = monitor.notices(f, [], state, 600 + hour * 3600, local_day, {'pilot', 'framer', 'jimbo'})
    told_count += len(lines) + (1 if shout else 0)
    if hour == 11:
        check('jimbo unreachable 11 hours says nothing, nor logs again', lines == [] and log == [])
check('nothing repeats within 24 hours, not even hourly', told_count == 0)
f = judge({'pilot': down, 'framer': down, 'jimbo': down}, state, now=600 + 24 * 3600)
lines, shout, log = monitor.notices(f, [], state, 600 + 24 * 3600, local_day, {'pilot', 'framer', 'jimbo'})
check('after 24 hours framer is told once as still open', len(lines) == 1 and lines[0].startswith('Still open after') and 'framer' in lines[0])
f = judge({'pilot': down, 'framer': down, 'jimbo': down}, state, now=600 + 60 * 3600)
lines, shout, log = monitor.notices(f, [], state, 600 + 60 * 3600, local_day, {'pilot', 'framer', 'jimbo'})
check('and never again after that', lines == [] and shout is None)

# Expected off: a machine Butler or Aaron switched off on purpose says nothing about being down, locked or awake.
monitor.CONFIG['quiet'] = {'start': '23:00', 'end': '07:00', 'summary': '07:30'}
now = 1000 * DAY
host, until, reason = monitor.parse_expect(['jimbo', 'down', 'until', '07:00', 'shut', 'down', 'for', 'the', 'night'], now, local_night)
check('expect until 07:00 at 02:00 lasts five hours', (host, until - now, reason) == ('jimbo', 5 * 3600, 'shut down for the night'))
check('expect for 3h', monitor.parse_expect(['framer', 'for', '3h'], now)[1] == now + 3 * 3600)
try:
    monitor.parse_expect(['../etc', 'down'], now)
    check('an unknown machine is refused', False)
except ValueError:
    check('an unknown machine is refused', True)
monitor.write_expect('framer', now + 3600, 'unplugged to move it', now)
monitor.write_expect('jimbo', now - 1, 'old mark', now - 7200)
expected = monitor.read_expected(now)
check('a live mark is read and an expired one dropped', set(expected) == {'framer'} and not os.path.exists(monitor.expect_path('jimbo')))
state = {}
judge({'framer': down}, state, now=now, expected=expected)
f = judge({'framer': down}, state, now=now + 900, expected=expected)
lines, shout, log = monitor.notices(f, [], state, now + 900, local_day, {'framer'})
check('expected-down framer is not told or shouted', levels(f) == {} and lines == [] and shout is None)
check('and the log says why it was kept quiet', log and log[0]['why'] == 'expected: unplugged to move it')
check('an expected Mac locked with keep-awake off gets no keep-awake action',
      monitor.choose_actions(judge({'piggys-MBP': healthy(keepawake='off', locked='yes')}, expected={'piggys-MBP': {'reason': 'put to sleep by Butler'}}), snap({})) == [('release-work', 'spike')])
check('a disk problem still counts while a machine is expected off',
      levels(judge({'piggys-MBP': healthy(disk_free_bytes=5 * GB)}, expected={'piggys-MBP': {'reason': 'x'}})) == {'piggys-MBP:disk': 'act'})
marks = {'framer': {'set': now, 'until': now + 3600, 'reason': 'x'}}
check('a mark holds while the machine is back for under 10 minutes', monitor.settle_expected(marks, snap({'framer': healthy(os='linux')}), now + 300) == [])
check('and ends once it is back and awake', monitor.settle_expected(marks, snap({'framer': healthy(os='linux')}), now + 700) == ['framer'] and marks == {})
marks = {'piggys-MBP': {'set': now, 'until': now + DAY, 'reason': 'x'}}
check('a slept Mac back with keep-awake still off stays expected', monitor.settle_expected(marks, snap({'piggys-MBP': healthy(keepawake='off')}), now + 3600) == [])

# Escalation: a problem is told once, again only when it gets worse.
state = {}
f = judge({'spike': healthy(os='linux', disk_free_bytes=18 * GB, disk_total_bytes=150 * GB)}, state, now=now)
lines, _, _ = monitor.notices(f, [], state, now, local_day)
check('a new disk warning is told once with what to do', len(lines) == 1 and 'Free some space' in lines[0])
f = judge({'spike': healthy(os='linux', disk_free_bytes=17 * GB, disk_total_bytes=150 * GB)}, state, now=now + 3 * 3600)
lines, _, _ = monitor.notices(f, [], state, now + 3 * 3600, local_day)
check('the same warning a little lower is not told again', lines == [])
f = judge({'spike': healthy(os='linux', disk_free_bytes=8 * GB, disk_total_bytes=150 * GB)}, state, now=now + 4 * 3600)
lines, shout, _ = monitor.notices(f, [], state, now + 4 * 3600, local_day)
check('crossing into act is told as worse and shouted', len(lines) == 1 and lines[0].startswith('Worse: ⚠️') and shout)
f = judge({'spike': healthy(os='linux')}, state, now=now + 5 * 3600)
lines, _, log = monitor.notices(f, [], state, now + 5 * 3600, local_day)
check('a resolution is never told, only logged later', lines == [] and log == [])
f = judge({'spike': healthy(os='linux')}, state, now=now + 5 * 3600 + 31 * 60)
lines, _, log = monitor.notices(f, [], state, now + 5 * 3600 + 31 * 60, local_day)
check('after 30 minutes gone it is logged as cleared', lines == [] and [e['route'] for e in log] == ['cleared'] and 'spike:disk' not in state['sent'])
flap = {}
for i, free in enumerate([18, 25, 18, 25, 18]):
    f = judge({'spike': healthy(os='linux', disk_free_bytes=free * GB, disk_total_bytes=150 * GB)}, flap, now=now + i * 600)
    lines, _, _ = monitor.notices(f, [], flap, now + i * 600, local_day)
    if i:
        check('a disk flapping at the edge is not told again (%d)' % i, lines == [])

# Silent findings: Claude accounts move on by themselves, busy turn slots are not stuck, Docker's cache is pruned daily.
check('one Claude account at 96% is only noted', levels(judge({}, claude={'personal': 96, 'work': 85})) == {})
check('every Claude account at 95% warns', levels(judge({}, claude={'personal': 96, 'work': 97})) == {'claude:all': 'warn'})

# Claude accounts.

# Runaway work.
work = {'running': 6, 'long': [{'id': 'x', 'title': 'Long one', 'started': 1000 * DAY - 4 * 3600}]}
check('a long change warns, many at once is only noted', levels(judge({}, work=work)) == {'work:long:x': 'warn'} and 'work:running' in noted(judge({}, work=work)))

# Failed units arrive investigated. butler-builders on 4 Nov: two runs failed at 12:42 and 12:42:38 with
# `could not push the digest; the next run tries again`, exit 1, and the run at 12:43:36 and every one after worked.
T0 = 1793756510.0  # 12:41:50 AEDT, Wed 4 Nov 2026


def jl(at, mid=None, msg='', own=False, **fields):
    e = {'__REALTIME_TIMESTAMP': str(int(at * 1e6)), 'MESSAGE': msg, '_PID': '4242' if own else '1',
         '_SYSTEMD_UNIT': 'butler-builders.service' if own else 'init.scope'}
    if mid:
        e['MESSAGE_ID'] = mid
    e.update(fields)
    return e


def failed_run(at):
    return [jl(at, '7d4958e842da4a758f6c1cdc7b36dcc5', 'Starting Rebuild the builders digest...'),
            jl(at + 20, msg='butler-builders: could not push the digest; the next run tries again', own=True),
            jl(at + 20.1, monitor.UNIT_EXIT, 'butler-builders.service: Main process exited, code=exited, status=1/FAILURE', EXIT_CODE='exited', EXIT_STATUS='1'),
            jl(at + 20.2, monitor.UNIT_RESULT, "butler-builders.service: Failed with result 'exit-code'.", UNIT_RESULT='exit-code'),
            jl(at + 20.3, 'be02cf6855d2428ba40df7e9d022f03d', 'Failed to start Rebuild the builders digest', JOB_RESULT='failed')]


def good_run(at):
    return [jl(at, '7d4958e842da4a758f6c1cdc7b36dcc5', 'Starting Rebuild the builders digest...'),
            jl(at + 15, msg='butler-builders: digest pushed, 122 lines', own=True),
            jl(at + 15.1, monitor.UNIT_SUCCESS, 'butler-builders.service: Deactivated successfully.'),
            jl(at + 15.2, monitor.UNIT_STARTED, 'Finished Rebuild the builders digest.', JOB_RESULT='done')]


bb = 'butler-builders.service'
key = 'spike:failed:' + bb
history = good_run(T0 - 120) + failed_run(T0) + failed_run(T0 + 28)
d = monitor.parse_unit_journal(bb, history)
check('the journal gives the streak, its exit and its cause', d['failed_runs'] == 2 and d['exit'] == 'exit 1'
      and d['cause'] == 'could not push the digest; the next run tries again' and d['recovered_at'] is None)
healed = monitor.parse_unit_journal(bb, history + good_run(T0 + 86))
check('a later good run ends the streak and records the recovery', healed['failed_runs'] == 0 and healed['fails_day'] == 2
      and healed['recovered_at'] == T0 + 86 + 15.1 and healed['cause'] == d['cause'])


def unit_spike(diag, failed=True, unit=bb):
    return {'spike': healthy(os='linux', failed_units=[unit] if failed else [], units={unit: diag}, on_battery=None, keepawake=None)}


now = T0 + 28 + 25
state = {}
f = judge(unit_spike(dict(d, state='failed', next_run=T0 + 150)), state, now=now)
lines, shout, log = monitor.notices(f, [], state, now, local_day)
check('the 12:42 failure, two runs and seconds old, is not told', lines == [] and shout is None and key in noted(f))
check('it is logged quietly with its cause', log and log[0]['route'] == 'kept' and 'could not push the digest' in log[0]['text'])
check('and choosing actions restarts nothing for it', not [a for a, _ in monitor.choose_actions(f, snap(unit_spike(d)))] or
      all(not a.startswith('restart:') for a, _ in monitor.choose_actions(f, snap(unit_spike(d)))))
now = T0 + 86 + 60
f = judge(unit_spike(dict(healed, state='inactive', next_run=now + 60), failed=False), state, now=now)
lines, _, log = monitor.notices(f, [], state, now, local_day)
check('the next run working is silent too, and logged as recovered with the cause', lines == [] and log and
      'recovered by itself' in log[0]['why'] and 'could not push the digest' in log[0]['text'])
check('so "what did you not tell me" names it', 'could not push the digest' in monitor.status_text(snap(unit_spike(healed, failed=False)), f, 'dry-run', now))

# Persistent: three runs in a row, still failing, is told once, diagnosed, never "read its journal".
runs3 = monitor.parse_unit_journal(bb, history + failed_run(T0 + 150))
now = T0 + 175
state = {}
f = judge(unit_spike(dict(runs3, state='failed', next_run=T0 + 270)), state, now=now, mode='dry-run')
lines, _, _ = monitor.notices(f, [], state, now, local_day)
check('three failed runs in a row are told', levels(f) == {key: 'warn'} and len(lines) == 1)
text = lines[0] if lines else ''
check('the notice says what, why, its state and what next', 'butler-builders on spike has failed 3 runs in a row since 12:42' in text
      and 'could not push the digest' in text and '(exit 1)' in text and 'still down' in text and 'fix it' in text)
check('no notice says "read its journal"', 'journal, or ask me' not in text and 'read its journal' not in text.lower())
check('and it is not told again next run', monitor.notices(judge(unit_spike(dict(runs3, state='failed')), state, now=now + 120), [], state, now + 120, local_day)[0] == [])
check('a butler unit told about is restarted when acting', ('restart:' + bb, 'spike') in monitor.choose_actions(f, snap(unit_spike(runs3))))

# One failure that nothing retries is told once it has stayed down 10 minutes.
one = monitor.parse_unit_journal(bb, failed_run(T0))
check('one failure 5 minutes down is only noted', levels(judge(unit_spike(dict(one, state='failed')), now=T0 + 320)) == {})
f = judge(unit_spike(dict(one, state='failed')), now=T0 + 20 + 601)
check('one failure still down after 10 minutes is told', levels(f) == {key: 'warn'} and 'has been down since 12:42' in f[0]['text'])

# Flapping: as many failures in a day as unitFailsPerDay, each recovered, is told though it is fine right now;
# the 7 self-healed push failures butler-builders had by 12:56 on 4 Nov are not.
day_bar = int(monitor.th('unitFailsPerDay'))


def flapping(n):
    runs = []
    for i in range(n):
        runs += failed_run(T0 - 23 * 3600 + i * 600) + good_run(T0 - 23 * 3600 + i * 600 + 120)
    return judge(unit_spike(dict(monitor.parse_unit_journal(bb, runs), state='inactive'), failed=False), now=T0)


check('seven self-healed failures in a day stay quiet', levels(flapping(7)) == {} and key in noted(flapping(7)))
f = flapping(day_bar)
check('%d failures in a day are told even when recovered' % day_bar, levels(f) == {key: 'warn'} and 'failed %d times in the last day' % day_bar in f[0]['text'])

# A failed unit whose journal could not be read is still told, saying so.
f = judge({'spike': healthy(os='linux', failed_units=['postgresql.service'], on_battery=None, keepawake=None)})
check('an unread failure is told, saying the journal could not be read', levels(f) == {'spike:failed:postgresql.service': 'warn'}
      and "couldn't read its journal" in f[0]['text'])

# A unit that retries itself and counts its own runs, backlogic-switch, goes through the same judging.
unit = 'backlogic-switch.service'
check('the streak unit is configured', unit in monitor.CONFIG['failStreaks'])


def streak(runs, running=None, failed=True):
    diag = {'failed_runs': runs, 'fails_day': runs, 'failed_since': 1000 * DAY - 60 * runs if runs else None,
            'last_fail': 1000 * DAY - 30 if runs else None, 'cause': 'plugin refresh failed', 'exit': 'exit 1',
            'state': 'failed' if failed else ('activating' if running else 'inactive'), 'running_seconds': running}
    return unit_spike(diag, failed=failed, unit=unit)


check('one failed run of a self-retrying unit is only noted', levels(judge(streak(1))) == {} and 'spike:failed:' + unit in noted(judge(streak(1))))
check('two failed runs are only noted', levels(judge(streak(2))) == {})
check('three failed runs in a row warn', levels(judge(streak(3))) == {'spike:failed:' + unit: 'warn'})
check('three in a row warn while the next run is going', levels(judge(streak(3, running=20, failed=False))) == {'spike:failed:' + unit: 'warn'})
check('a run going 10 minutes warns as stuck', levels(judge(streak(0, running=601, failed=False))) == {'spike:stuck:' + unit: 'warn'})
check('a run going 5 minutes raises nothing', judge(streak(0, running=300, failed=False)) == [])

# Action choice: only the table's safe actions, nothing on pilot.
machines = {'spike': healthy(os='linux', disk_free_bytes=5 * GB, failed_units=['butler-memory-pull.service', 'butler.service', 'postgresql.service']),
            'pilot': healthy(keepawake='off'), 'piggys-MBP': healthy(keepawake='off')}
f = judge(machines)
actions = monitor.choose_actions(f, snap(machines))
names = [a for a, _ in actions]
check('spike disk act picks every disk action', all(a in names for a in monitor.SPIKE_DISK_ACTIONS))
check('only a butler-owned failed unit is restarted', [a for a in names if a.startswith('restart:')] == ['restart:butler-memory-pull.service'])
check('keep-awake back on for piggys-MBP alone', [h for a, h in actions if a == 'keepawake-on'] == ['piggys-MBP'])
check('spike tight holds work', ('hold-work', 'spike') in actions)

# Acting: dry-run logs, off is silent, on runs, each at most hourly per machine.
calls = []


def doer(name, host):
    calls.append((name, host))
    return '5 GB free', '30 GB free'


state = {}
results = monitor.act(actions, state, 'dry-run', 0, doer)
check('dry-run does nothing but says what it would', calls == [] and all(r['result'] == 'dry-run' for r in results) and results)
check('dry-run says it again only after an hour', monitor.act(actions, state, 'dry-run', 600, doer) == [])
check('mode off neither acts nor logs', monitor.act(actions, {}, 'off', 0, doer) == [] and calls == [])
state = {}
results = monitor.act(actions, state, 'on', 0, doer)
check('on runs each action once', len(calls) == len(actions) and all(r['result'] == 'done' for r in results))
check('an action line has before and after', '5 GB free → 30 GB free' in results[0]['line'])
calls.clear()
monitor.act(actions, state, 'on', 1800, doer)
check('on repeats nothing within the hour, the unit restart never while it stays failed', calls == [])
monitor.act(actions, state, 'on', 3700, doer)
check('after an hour the disk actions may run again, not the restart', ('restart:butler-memory-pull.service', 'spike') not in calls and ('docker-prune', 'spike') in calls)

# Quiet hours: warnings and real actions wait for one short morning list; urgent items do not; dry-run plans never show.
state = {}
f = judge({'a': healthy(disk_free_bytes=18 * GB, disk_total_bytes=100 * GB), 'b': healthy(disk_free_bytes=5 * GB)}, state)
did = [{'action': 'docker-prune', 'result': 'done', 'line': "Did: clear Docker's build cache, 5 GB free → 30 GB free."},
       {'action': 'keepawake-on', 'result': 'dry-run', 'line': 'Would turn piggys-MBP keep-awake back on (acting is in dry-run).'},
       {'action': 'hold-work', 'result': 'done', 'line': 'Did: hold new change sessions.'}]
lines, shout, log = monitor.notices(f, did, state, 1000 * DAY, local_night)
check('at night only the urgent item notifies', len(lines) == 1 and 'b' in lines[0] and shout)
check('the warning and the real action wait overnight, the dry-run and hold do not', [i['key'] for i in state['overnight']] == ['a:disk', 'action'])
check('the held one is logged as held', any(e['route'] == 'held for the morning' and e['key'] == 'a:disk' for e in log))
summary = monitor.morning(state, local_morning, f)
check('the morning summary is one short list', summary and summary.startswith('Overnight, machines:') and summary.count('\n- ') == 2 and 'Still open' not in summary)
check('and only once that morning', monitor.morning(state, local_morning, f) is None)
state = {}
lines, _, _ = monitor.notices([], [did[1]], state, 1000 * DAY, local_night)
check('a quiet night sends no morning summary', lines == [] and monitor.morning(state, local_morning, []) is None)
lines, _, _ = monitor.notices([], [did[1], did[2]], {}, 1000 * DAY, local_day)
check('by day a dry-run plan or the hold flag is not told either', lines == [])

# A Mac locked at night is a line in the morning list, not a notice, and is not told again by day.
state = {}
f = judge({'piggys-MBP': healthy(locked='yes')}, state)
lines, shout, log = monitor.notices(f, [], state, 1000 * DAY, local_night)
check('a night lock is no notice', lines == [] and shout is None and log[0]['route'] == 'noted for the morning')
lines, _, _ = monitor.notices(judge({'piggys-MBP': healthy(locked='yes')}, state), [], state, 1000 * DAY + 6 * 3600, local_morning)
summary = monitor.morning(state, local_morning, f)
check('it is not told by day, only in the morning list', lines == [] and summary and "piggys-MBP's screen is locked" in summary)
lines, _, _ = monitor.notices(judge({'piggys-MBP': healthy(locked='yes')}), [], {}, 1000 * DAY, local_day)
check('a lock by day is told, with what to do', len(lines) == 1 and 'Unlock it' in lines[0])

# A fake Mac's reading.
raw = monitor.parse_pairs('cores=8\nload=4.10 5.20 6.90\nmemfree=46\npressure=1\ndisk_total=494384795648\n'
                          'disk_free=70000000000\npower=Battery Power\nbattery=78\nlocked=no\nkeepawake=on\n')
m = monitor.normalise('macos', raw)
lm = monitor.normalise('macos', monitor.parse_pairs('locked=yes\nlockwhy=1793000000\t01:56\tthe screen saver started after 20 minutes idle and locked the screen\n'))
check('a Mac lock cause normalises', lm['lock_at'] == '01:56' and lm['lock_cause'].startswith('the screen saver'))
check('a Mac reading normalises', m['load15'] == 6.9 and m['mem_free_ratio'] == 0.46 and m['on_battery'] and m['battery'] == 78 and m['keepawake'] == 'on')
w = monitor.normalise('windows', monitor.parse_pairs('cores=16\nmem_total_kb=16000000\nmem_free_kb=3900000\ndisk_total=500000000000\ndisk_free=23900000000\nlocked=no\nkeepawake=on\n'))
check('a Windows reading normalises', abs(w['mem_free_ratio'] - 0.24375) < 1e-9 and w['disk_free_bytes'] == 23.9e9 and 'on_battery' not in w)
check('status and metrics render', 'pilot' in monitor.status_text(snap(baseline), [], 'dry-run', 0) and
      'butler_monitor_host_up{machine="pilot"} 1.0' in monitor.prom_lines(snap(baseline), [], 'dry-run', 0))

# Butler's turn pool: a turn waiting over 2 minutes, or every slot busy for 15, warns once.
now = 1000 * DAY
pool = {'cap': 4, 'reserved': 2, 'backoff': None, 'running': 4, 'interactive': 2, 'background': 2, 'queued': 1,
        'oldestQueuedAt': (now - 90) * 1000, 'runningStartedAt': [], 'fullSince': (now - 10 * 60) * 1000}
check('a short wait and busy slots for 10 minutes raise nothing', not [f for f in judge({}, turns=pool, now=now) if f['host'] == 'spike'])
pool.update(oldestQueuedAt=(now - 150) * 1000, fullSince=(now - 16 * 60) * 1000)
f = judge({}, turns=pool, now=now)
check('a turn waiting over 2 minutes and slots busy over 15 are only noted', levels(f) == {} and noted(f) == {'butler:queue', 'butler:slots'})
pool.update(oldestQueuedAt=(now - 31 * 60) * 1000)
state = {}
f = judge({}, state, turns=pool, now=now)
lines, _, _ = monitor.notices(f, [], state, now, local_day)
again, _, _ = monitor.notices(judge({}, state, turns=pool, now=now + 4 * 3600), [], state, now + 4 * 3600, local_day)
check('a turn stuck for 30 minutes is told once', levels(f) == {'butler:queue': 'warn'} and len(lines) == 1 and again == [])
metrics = monitor.prom_lines(snap({}, turns=pool), [], 'dry-run', now)
check('the pool is charted', 'butler_turns_queued 1' in metrics and 'butler_turns_oldest_queued_seconds 1860' in metrics and 'butler_turns_slots_busy_seconds 960' in metrics)
check('back off at 90% of a session or week', monitor.backoff({'personal': {'session': 91, 'weekly': 20}, 'work': {'weekly': 50}}) == 'the Claude personal session at 91%'
      and monitor.backoff({'personal': {'session': 89}, 'work': {'weekly': 66}}) is None)
limits = os.path.join(tmp, 'limits')
os.makedirs(limits)
with open(os.path.join(limits, 'claude-limits-work.prom'), 'w') as fh:
    fh.write('claude_limit_percent{account="work",kind="session",model=""} 12\nclaude_limit_percent{account="work",kind="weekly_all",model=""} 93\n')
monitor.CONFIG['limits'] = limits
check('both kinds of limit are read', monitor.read_limit_kinds() == {'work': {'session': 12.0, 'weekly': 93.0}})
call_state = os.path.join(tmp, 'call.json')
monitor.CONFIG['callState'] = call_state
with open(call_state, 'w') as fh:
    json.dump({'live': False, 'updatedAt': now * 1000, 'turns': pool}, fh)
check('the pool is read from the call state file while fresh', monitor.read_turns(now) == pool and monitor.read_turns(now + 120) is None)

if failures:
    print('%d failed' % len(failures))
    sys.exit(1)
print('all passed')
