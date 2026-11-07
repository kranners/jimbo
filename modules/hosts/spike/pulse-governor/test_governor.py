"""The usage governor against fixture Prometheus answers and sinks, offline: python3 test_governor.py governor.py"""

import importlib.util
import json
import os
import sys
import tempfile
import urllib.parse

spec = importlib.util.spec_from_file_location('governor', sys.argv[1])
g = importlib.util.module_from_spec(spec)
spec.loader.exec_module(g)

failures = []


def check(name, condition, detail=''):
    print(('PASS ' if condition else 'FAIL ') + name + ((': ' + str(detail)) if not condition else ''))
    if not condition:
        failures.append(name)


# Sat 7 Nov 2026 18:00 Melbourne.
NOW = 1794034800
DAY = 86400
STEP = 600


def history(start_level, per_hour, days, reset_every=7 * DAY, capped_from=None):
    """A steady burn of per_hour, resetting weekly, from days ago until now."""
    points = []
    t = NOW - days * DAY
    level = start_level
    last_reset = t
    while t <= NOW:
        if t - last_reset >= reset_every:
            level, last_reset = 0.0, t
        value = min(100.0, level)
        if capped_from is not None and t >= capped_from:
            value = 100.0
        points.append([t, str(value)])
        level += per_hour * STEP / 3600
        t += STEP
    return points


def fake_prometheus(series):
    def fetch(url):
        query = urllib.parse.parse_qs(urllib.parse.urlparse(url).query)['query'][0]
        rows = []
        for account, data in series.items():
            if query.startswith('claude_limit_percent{kind=~'):
                for kind in ('weekly_all', 'session'):
                    if kind in data:
                        rows.append({'metric': {'account': account, 'kind': kind}, 'value': [NOW, str(data[kind])]})
            elif query.startswith('claude_limit_resets_at_seconds'):
                for kind, key in (('weekly_all', 'reset'), ('session', 'sessionReset')):
                    if key in data:
                        rows.append({'metric': {'account': account, 'kind': kind}, 'value': [NOW, str(data[key])]})
            elif query.startswith('time()'):
                rows.append({'metric': {'file': '/var/lib/claude-limits/claude-limits-%s.prom' % account},
                             'value': [NOW, str(data.get('age', 60))]})
            elif query == 'claude_limit_percent{kind="weekly_all"}':
                rows.append({'metric': {'account': account, 'kind': 'weekly_all'}, 'values': data['history']})
        return rows
    return fetch


sinks_dir = tempfile.mkdtemp()
with open(os.path.join(sinks_dir, 'maintenance.yaml'), 'w') as f:
    f.write('''
- id: machines-disk
  title: Disk and cache sweep
  value: high
  effort: s
- id: docs-tests
  value: low
  effort: m
- id: paused-one
  value: high
  effort: xs
  paused: true
''')
with open(os.path.join(sinks_dir, 'work.json'), 'w') as f:
    json.dump([{'id': 'backlogic-drain', 'value': 'high', 'effort': 'l', 'percent': 30, 'account': 'beta'}], f)
with open(os.path.join(sinks_dir, 'broken.yaml'), 'w') as f:
    f.write('- title: no id here\n')

config = g.load_config()
config.update(sinks=sinks_dir, state=os.path.join(sinks_dir, 'state.json'))

series = {
    # Burns 0.2%/h, at 10% with 3 days left: lands far short, so boost.
    'alpha': {'weekly_all': 10, 'session': 20, 'reset': NOW + 3 * DAY, 'sessionReset': NOW + 3600,
              'history': history(0, 0.2, 21)},
    # Burns 1.5%/h, at 70% with 2 days left: would run out, so conserve.
    'beta': {'weekly_all': 70, 'session': 40, 'reset': NOW + 2 * DAY, 'history': history(0, 1.5, 21)},
    # Spent until its reset.
    'gamma': {'weekly_all': 100, 'reset': NOW + 0.5 * DAY, 'history': history(0, 3.0, 21)},
    # Session at its limit though the week has room.
    'delta': {'weekly_all': 30, 'session': 100, 'reset': NOW + 5 * DAY, 'history': history(0, 0.1, 21)},
}

state = g.govern(config, now=NOW, fetch=fake_prometheus(series))
by = {a['account']: a for a in state['accounts']}

check('every account judged', sorted(by) == ['alpha', 'beta', 'delta', 'gamma'], sorted(by))
check('alpha learns its burn', abs(by['alpha']['burnPerHour'] - 0.2) < 0.05, by['alpha']['burnPerHour'])
check('alpha projects about 24% at its reset', 20 < by['alpha']['projected'] < 30, by['alpha']['projected'])
check('alpha is boost', by['alpha']['mode'] == 'boost', by['alpha'])
check('alpha waste is most of its week', by['alpha']['waste'] > 65, by['alpha']['waste'])
check('alpha spare leaves the floor', by['alpha']['spare'] <= 100 - by['alpha']['floor'] - by['alpha']['projected'] + 0.2)
check('floor stays within bounds', all(config['floorMin'] <= a['floor'] <= config['floorMax']
                                      for a in state['accounts'] if a['mode'] not in ('unknown', 'capped')))
check('beta is conserve', by['beta']['mode'] == 'conserve', by['beta'])
check('beta says when it runs out', by['beta']['runsOutAt'] and NOW < by['beta']['runsOutAt'] < series['beta']['reset'])
check('gamma is capped', by['gamma']['mode'] == 'capped', by['gamma']['mode'])
check('capped history does not count as burn', by['gamma']['burnPerHour'] > 2, by['gamma']['burnPerHour'])
check('delta is session-capped', by['delta']['mode'] == 'session-capped', by['delta']['mode'])
check('start order puts boost first and leaves capped out', state['startOrder'] == ['alpha', 'beta'], state['startOrder'])
check('runner gets no sessions on a capped account', state['runner']['gamma']['sessions'] == 0)
check('runner gets every session on a boost account', state['runner']['alpha']['sessions'] == config['runnerSessions'])
check('runner keeps the floor in its ceiling', state['runner']['alpha']['weeklyPercentMax'] == round(100 - by['alpha']['floor']))

ids = [s['id'] for s in state['sinks']]
check('sinks are ranked by value over effort', ids[0] == 'machines-disk', ids)
check('a paused sink is left out', 'paused-one' not in ids, ids)
check('a broken sink file is reported', any('broken.yaml' in e for e in state['errors']), state['errors'])
released = {s['id']: s.get('account') for s in state['sinks'] if s['released']}
check('alpha releases the sinks it can cover', released.get('machines-disk') == 'alpha' and released.get('docs-tests') == 'alpha', released)
check('a sink for a conserving account is held', 'backlogic-drain' not in released, released)
check('nothing is applied', state['applied'] is False)

# Far from its reset with a small spare, nothing is released yet.
far = {'alpha': dict(series['alpha'], weekly_all=60, reset=NOW + 6 * DAY)}
far_state = g.govern(config, now=NOW, fetch=fake_prometheus(far))
check('far from the reset with a small spare holds sinks back',
      not any(s['released'] for s in far_state['sinks']), far_state['accounts'][0])

# Prometheus down: an error, no accounts, still a state.
def down(url):
    raise OSError('connection refused')
broken = g.govern(config, now=NOW, fetch=down)
check('prometheus down is reported, not raised', broken['accounts'] == [] and broken['errors'][0].startswith('prometheus'))

g.write_state(state, config['state'])
check('state file is world readable', oct(os.stat(config['state']).st_mode & 0o777) == '0o644')
text = g.status(state, config)
check('status names each account and the start order', all(n in text for n in by) and 'Start new sessions on: alpha, beta' in text, text)
print(text)

sys.exit(1 if failures else 0)
