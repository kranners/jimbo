"""Fixture tests for butler-monitor: thresholds, holds, repeats, quiet hours and action choice, on fake machines."""

import importlib.util
import json
import os
import sys
import tempfile
import time

spec = importlib.util.spec_from_file_location('monitor', sys.argv[1])
monitor = importlib.util.module_from_spec(spec)
spec.loader.exec_module(monitor)

with open(sys.argv[2]) as f:
    monitor.CONFIG.update(json.load(f))
tmp = tempfile.mkdtemp()
monitor.CONFIG.update(state=tmp, holdFile=os.path.join(tmp, 'hold'), group=None)

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


def snap(machines, claude=None, work=None):
    return {'machines': machines, 'claude': claude or {}, 'work': work}


def judge(machines, state=None, now=1000 * DAY, **kw):
    state = {} if state is None else state
    return monitor.settle(monitor.evaluate(snap(machines, **kw), state, now), state, now)


def levels(findings):
    return {f['key']: f['level'] for f in findings}


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
check('memory 6% warns at first', levels(judge({'a': healthy(mem_free_ratio=0.06)}, state, now=0)) == {'a:memory': 'warn'})
check('memory 6% still warn after 4 min', levels(judge({'a': healthy(mem_free_ratio=0.06)}, state, now=240)) == {'a:memory': 'warn'})
check('memory 6% acts after 5 min', levels(judge({'a': healthy(mem_free_ratio=0.06)}, state, now=300)) == {'a:memory': 'act'})
check('memory hold resets once it recovers', levels(judge({'a': healthy()}, state, now=360)) == {} and
      levels(judge({'a': healthy(mem_free_ratio=0.06)}, state, now=420)) == {'a:memory': 'warn'})

check('critical pressure acts', levels(judge({'a': healthy(pressure='critical')})) == {'a:pressure': 'act'})
check('load 2.5x cores warns', levels(judge({'a': healthy(load15=20, load_ratio=2.5)})) == {'a:load': 'warn'})

# Battery counts only on battery with keep-awake on.
check('battery 35% warns', levels(judge({'a': healthy(on_battery=True, battery=35)})) == {'a:battery': 'warn'})
check('battery 15% acts', levels(judge({'a': healthy(on_battery=True, battery=15)})) == {'a:battery': 'act'})
check('battery 15% with keep-awake off is fine', levels(judge({'a': healthy(on_battery=True, battery=15, keepawake='off')})) == {})
check('locked with keep-awake on warns', levels(judge({'a': healthy(locked='yes')})) == {'a:locked': 'warn'})
check('keep-awake off on piggys-MBP acts', levels(judge({'piggys-MBP': healthy(keepawake='off')})) == {'piggys-MBP:keepawake': 'act'})
check('keep-awake off on pilot is its default', levels(judge({'pilot': healthy(keepawake='off')})) == {})

# Down: 10 minutes, then once for a laptop, hourly and urgent for framer.
state = {}
down = {'up': False, 'why': 'does not answer on ssh'}
judge({'pilot': down, 'framer': down}, state, now=0)
f = judge({'pilot': down, 'framer': down}, state, now=600)
check('down for 10 minutes is noticed', levels(f) == {'pilot:down': 'warn', 'framer:down': 'act'})
check('framer down is urgent, pilot not', {x['key']: x['urgent'] for x in f} == {'pilot:down': False, 'framer:down': True})
lines, shout = monitor.notices(f, [], state, 600, local_day, {'pilot', 'framer'})
check('both down notices go out once', len(lines) == 2 and shout and 'framer' in shout)
f = judge({'pilot': down, 'framer': down}, state, now=1800)
lines, shout = monitor.notices(f, [], state, 1800, local_day, {'pilot', 'framer'})
check('no repeat within the hour', lines == [] and shout is None)
f = judge({'pilot': down, 'framer': down}, state, now=4300)
lines, shout = monitor.notices(f, [], state, 4300, local_day, {'pilot', 'framer'})
check('framer repeats hourly, pilot never', len(lines) == 1 and 'framer' in lines[0])

# Claude accounts.
check('weekly 85% warns, 96% acts', levels(judge({}, claude={'personal': 96, 'work': 85})) == {'claude:personal': 'act', 'claude:work': 'warn'})

# Runaway work.
work = {'running': 6, 'long': [{'id': 'x', 'title': 'Long one', 'started': 1000 * DAY - 4 * 3600}]}
check('too many changes and a long one warn', levels(judge({}, work=work)) == {'work:running': 'warn', 'work:long:x': 'warn'})

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

# Quiet hours: warnings wait for the morning, urgent and real actions do not.
state = {}
f = judge({'a': healthy(disk_free_bytes=18 * GB, disk_total_bytes=100 * GB), 'b': healthy(disk_free_bytes=5 * GB)}, state)
lines, shout = monitor.notices(f, [], state, 1000 * DAY, local_night)
check('at night only the urgent item notifies', len(lines) == 1 and 'b' in lines[0] and shout)
check('the warning waits overnight', len(state['overnight']) == 1)
summary = monitor.morning(state, local_morning, f)
check('the morning summary lists it once', summary and 'a\'s disk' in summary and state.get('overnight') is None)
check('and only once that morning', monitor.morning(state, local_morning, f) is None)

# A fake Mac's reading.
raw = monitor.parse_pairs('cores=8\nload=4.10 5.20 6.90\nmemfree=46\npressure=1\ndisk_total=494384795648\n'
                          'disk_free=70000000000\npower=Battery Power\nbattery=78\nlocked=no\nkeepawake=on\n')
m = monitor.normalise('macos', raw)
check('a Mac reading normalises', m['load15'] == 6.9 and m['mem_free_ratio'] == 0.46 and m['on_battery'] and m['battery'] == 78 and m['keepawake'] == 'on')
w = monitor.normalise('windows', monitor.parse_pairs('cores=16\nmem_total_kb=16000000\nmem_free_kb=3900000\ndisk_total=500000000000\ndisk_free=23900000000\nlocked=no\nkeepawake=on\n'))
check('a Windows reading normalises', abs(w['mem_free_ratio'] - 0.24375) < 1e-9 and w['disk_free_bytes'] == 23.9e9 and 'on_battery' not in w)
check('status and metrics render', 'pilot' in monitor.status_text(snap(baseline), [], 'dry-run', 0) and
      'butler_monitor_host_up{host="pilot"} 1.0' in monitor.prom_lines(snap(baseline), [], 'dry-run', 0))

if failures:
    print('%d failed' % len(failures))
    sys.exit(1)
print('all passed')
