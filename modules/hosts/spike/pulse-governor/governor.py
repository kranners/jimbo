"""Pulse's usage governor: be across each Claude account's usage, project it to its reset and say how to spend the rest.

It spends no tokens. Each run reads every account's weekly and session limits from Prometheus, where claude-limits'
textfiles land, learns how fast each account burns by hour of the week from the last weeks, projects each week to its
reset with a band, and works out what would be wasted: the budget left at the reset beyond a floor kept for Aaron's own
turns. It then ranks the token sinks in butler's memory's pulse/sinks/ and releases those the spare budget covers,
picks the order new sessions should start on, and says what the backlogic runner's account ceilings would be, all into
one JSON file for Butler, the conductor and the runner to read. It changes nothing itself.

    governor.py run      read Prometheus and the sinks, write the state file and print the status
    governor.py status   print the last state file's status
    governor.py json     print the last state file
    governor.py sinks    print the ranked sinks and which are released
"""

import json
import math
import os
import sys
import time
import urllib.parse
import urllib.request
from datetime import datetime, timezone

try:
    from zoneinfo import ZoneInfo
except ImportError:  # pragma: no cover
    ZoneInfo = None

try:
    import yaml
except ImportError:  # pragma: no cover
    yaml = None

DEFAULTS = {
    'prometheus': 'http://127.0.0.1:9090',
    'state': '/var/lib/pulse-governor/governor.json',
    'sinks': '/run/pulse-governor/sinks',
    'timezone': 'Australia/Melbourne',
    'historyDays': 28,
    'stepSeconds': 600,
    # Aaron's waking hours, from pulse's interrupt policy: his own turns happen then.
    'awake': ['08:30', '23:00'],
    # The floor kept for his own turns: this much of a week per waking hour left before the reset, within bounds.
    'interactivePerAwakeHour': 0.5,
    'floorMin': 3.0,
    'floorMax': 12.0,
    # Spare budget worth releasing sinks for, and how close to the reset small spares are released anyway.
    'boostMin': 5.0,
    'releaseWindowHours': 48,
    'releaseAnywayPercent': 20.0,
    'sessionHigh': 85.0,
    # The runner's sessions gate, scaled per account by its mode.
    'runnerSessions': 64,
}

VALUE = {'high': 3.0, 'med': 2.0, 'medium': 2.0, 'low': 1.0}
EFFORT = {'xs': 1.0, 's': 2.0, 'm': 4.0, 'l': 8.0, 'xl': 16.0}
# What a sink costs, in percent of one account's week, when it gives no estimate of its own.
EFFORT_PERCENT = {'xs': 0.5, 's': 1.0, 'm': 3.0, 'l': 8.0, 'xl': 15.0}
SHARE = {'boost': 1.0, 'steady': 0.75, 'conserve': 0.25, 'session-capped': 0.0, 'capped': 0.0, 'unknown': 0.5}


def load_config(path=None):
    config = dict(DEFAULTS)
    if path:
        with open(path) as f:
            config.update(json.load(f))
    return config


def zone(config):
    if ZoneInfo is None:
        return timezone.utc
    try:
        return ZoneInfo(config['timezone'])
    except Exception:
        return timezone.utc


# Prometheus.

def prom(config, path, params, fetch=None):
    url = config['prometheus'].rstrip('/') + path + '?' + urllib.parse.urlencode(params)
    if fetch:
        return fetch(url)
    with urllib.request.urlopen(url, timeout=20) as response:
        body = json.load(response)
    if body.get('status') != 'success':
        raise RuntimeError('prometheus answered %s' % body.get('status'))
    return body['data']['result']


def read_prometheus(config, now, fetch=None):
    """Each account's current reading, its resets and its weekly history, as plain dicts."""
    accounts = {}
    for row in prom(config, '/api/v1/query', {'query': 'claude_limit_percent{kind=~"weekly_all|session"}'}, fetch):
        account, kind = row['metric'].get('account'), row['metric'].get('kind')
        if not account:
            continue
        accounts.setdefault(account, {})['weekly' if kind == 'weekly_all' else 'session'] = float(row['value'][1])
        accounts[account]['readAt'] = float(row['value'][0])
    for row in prom(config, '/api/v1/query',
                    {'query': 'claude_limit_resets_at_seconds{kind=~"weekly_all|session"}'}, fetch):
        account, kind = row['metric'].get('account'), row['metric'].get('kind')
        if account in accounts:
            key = 'weeklyResetsAt' if kind == 'weekly_all' else 'sessionResetsAt'
            accounts[account][key] = float(row['value'][1])
    # The textfiles' age, so a reading the endpoint kept refusing reads as stale.
    for row in prom(config, '/api/v1/query',
                    {'query': 'time() - node_textfile_mtime_seconds{file=~".*claude-limits-.*"}'}, fetch):
        name = os.path.basename(row['metric'].get('file', ''))
        account = name[len('claude-limits-'):-len('.prom')] if name.endswith('.prom') else None
        if account in accounts:
            accounts[account]['ageSeconds'] = float(row['value'][1])
    start = now - config['historyDays'] * 86400
    for row in prom(config, '/api/v1/query_range', {
        'query': 'claude_limit_percent{kind="weekly_all"}',
        'start': int(start), 'end': int(now), 'step': config['stepSeconds'],
    }, fetch):
        account = row['metric'].get('account')
        if account in accounts:
            accounts[account]['history'] = [(float(t), float(v)) for t, v in row['values']]
    return accounts


# Learning and projecting.

def hour_of_week(ts, tz):
    local = datetime.fromtimestamp(ts, tz)
    return local.weekday() * 24 + local.hour


def learn(history, tz, step):
    """Burn in percent of the week per hour, by hour of the week, from the history.

    A drop is a reset, and readings at the limit are left out, since an account at 100% burns nothing by choice.
    """
    burned = [0.0] * 168
    hours = [0.0] * 168
    days = {}
    for (t0, v0), (t1, v1) in zip(history, history[1:]):
        gap = t1 - t0
        if gap <= 0 or gap > 3 * step or v0 >= 99.5:
            continue
        delta = v1 - v0
        if delta < -1:
            continue
        delta = max(0.0, delta)
        bucket = hour_of_week(t0, tz)
        burned[bucket] += delta
        hours[bucket] += gap / 3600
        day = datetime.fromtimestamp(t0, tz).date()
        days[day] = days.get(day, 0.0) + delta
    observed = sum(hours)
    overall = sum(burned) / observed if observed else 0.0
    rates = [burned[i] / hours[i] if hours[i] >= 1 else None for i in range(168)]
    # Day to day spread of the burn, for the band; full days alone.
    totals = list(days.values())[1:-1]
    if len(totals) >= 3:
        mean = sum(totals) / len(totals)
        spread = math.sqrt(sum((x - mean) ** 2 for x in totals) / len(totals)) / mean if mean > 0 else 1.0
    else:
        spread = 0.5
    return {'rates': rates, 'overall': overall, 'observedHours': round(observed, 1),
            'spread': min(1.0, max(0.2, spread))}


def awake(ts, tz, config):
    local = datetime.fromtimestamp(ts, tz)
    minute = local.hour * 60 + local.minute
    start, end = [int(x[:2]) * 60 + int(x[3:]) for x in config['awake']]
    return start <= minute < end if start < end else (minute >= start or minute < end)


def project(model, now, reset, tz, config):
    """Organic burn from now to the reset, and the waking hours in it."""
    organic = 0.0
    awake_hours = 0.0
    t = now
    while t < reset:
        span = min(3600.0, reset - t) / 3600
        rate = model['rates'][hour_of_week(t, tz)]
        organic += (model['overall'] if rate is None else rate) * span
        if awake(t, tz, config):
            awake_hours += span
        t += 3600
    return organic, awake_hours


def judge(account, data, now, tz, config):
    weekly = data.get('weekly')
    reset = data.get('weeklyResetsAt')
    out = {'account': account, 'weekly': weekly, 'session': data.get('session'),
           'weeklyResetsAt': reset, 'sessionResetsAt': data.get('sessionResetsAt'),
           'readingAgeMinutes': round(data['ageSeconds'] / 60) if 'ageSeconds' in data else None}
    if weekly is None or reset is None or reset <= now:
        out.update(mode='unknown', why='no current weekly reading or reset', spare=0.0, waste=0.0)
        return out
    model = learn(data.get('history', []), tz, config['stepSeconds'])
    organic, awake_hours = project(model, now, reset, tz, config)
    hours_left = (reset - now) / 3600
    projected = weekly + organic
    band = [weekly + organic * (1 - model['spread']), weekly + organic * (1 + model['spread'])]
    floor = min(config['floorMax'], max(config['floorMin'], awake_hours * config['interactivePerAwakeHour']))
    floor = min(floor, max(0.0, 100 - weekly))
    spare = max(0.0, 100 - floor - projected)
    waste = max(0.0, 100 - min(100.0, projected))
    runs_out = None
    if projected >= 100 and weekly < 100:
        # When the week would run out at the learnt burn, by walking the hours forward.
        level, t = weekly, now
        while t < reset and level < 100:
            rate = model['rates'][hour_of_week(t, tz)]
            level += (model['overall'] if rate is None else rate) * min(3600.0, reset - t) / 3600
            t += 3600
        runs_out = min(t, reset)
    session = data.get('session')
    if weekly >= 99.5:
        mode, why = 'capped', 'the week is spent until it resets'
    elif session is not None and session >= 99.5:
        mode, why = 'session-capped', 'its 5-hour session is spent'
    elif projected >= 100 - floor / 2:
        mode, why = 'conserve', 'at its usual burn it reaches the limit before the reset, eating the floor'
    elif spare >= config['boostMin']:
        mode, why = 'boost', 'about %.0f%% of the week would go unused at the reset' % spare
    else:
        mode, why = 'steady', 'its usual burn lands it near the limit at the reset'
    out.update(
        mode=mode, why=why, hoursLeft=round(hours_left, 1), organic=round(organic, 1),
        projected=round(projected, 1), band=[round(b, 1) for b in band], floor=round(floor, 1),
        spare=round(spare, 1), waste=round(waste, 1),
        extraPercentPerHour=round(spare / hours_left, 2) if hours_left > 0 else 0.0,
        runsOutAt=runs_out, burnPerHour=round(model['overall'], 3), observedHours=model['observedHours'],
        sessionHigh=session is not None and session >= config['sessionHigh'],
    )
    return out


def start_order(judged):
    """Accounts new sessions should start on, the one with the most budget to lose per hour first."""
    usable = [a for a in judged if a['mode'] in ('boost', 'steady', 'conserve') and not a.get('sessionHigh')]
    rank = {'boost': 0, 'steady': 1, 'conserve': 2}
    usable.sort(key=lambda a: (rank[a['mode']], -a.get('extraPercentPerHour', 0), a.get('projected', 100)))
    return [a['account'] for a in usable]


def runner_ceilings(judged, config):
    """What the backlogic runner's account settings would be: how far into each week to go, and a share of sessions."""
    ceilings = {}
    for a in judged:
        share = SHARE.get(a['mode'], 0.5)
        if a.get('sessionHigh') and share:
            share = min(share, 0.25)
        weekly_max = round(100 - a.get('floor', DEFAULTS['floorMin'])) if a['mode'] != 'unknown' else None
        ceilings[a['account']] = {
            'weeklyPercentMax': weekly_max,
            'sessionPercentMax': config['sessionHigh'],
            'sessions': int(round(config['runnerSessions'] * share)),
        }
    return ceilings


# Sinks.

def load_sinks(directory):
    sinks, errors = [], []
    try:
        names = sorted(os.listdir(directory))
    except OSError:
        return sinks, ['no sinks folder at %s' % directory]
    for name in names:
        if name.startswith('.') or not name.endswith(('.yaml', '.yml', '.json')):
            continue
        path = os.path.join(directory, name)
        try:
            with open(path) as f:
                text = f.read()
            items = json.loads(text) if name.endswith('.json') else (yaml.safe_load(text) if yaml else None)
            if items is None:
                raise ValueError('cannot read YAML here')
            for item in items if isinstance(items, list) else [items]:
                if not isinstance(item, dict) or not item.get('id'):
                    raise ValueError('each sink needs an id')
                item = dict(item)
                item['file'] = name
                sinks.append(item)
        except Exception as error:
            errors.append('%s: %s' % (name, error))
    return sinks, errors


def score(sink):
    value = VALUE.get(str(sink.get('value', 'med')).lower(), 2.0)
    effort = EFFORT.get(str(sink.get('effort', 's')).lower(), 2.0)
    return round(value / effort * (1 + float(sink.get('boost', 0))), 3)


def cost(sink):
    if sink.get('percent') is not None:
        return float(sink['percent'])
    return EFFORT_PERCENT.get(str(sink.get('effort', 's')).lower(), 1.0)


def release(sinks, judged, config):
    """Ranks the sinks and releases those the accounts' spare budget covers, nearest reset first."""
    ranked = sorted((s for s in sinks if not s.get('paused')), key=lambda s: (-score(s), s['id']))
    budget = {}
    for a in judged:
        if a['mode'] not in ('boost', 'steady') or a.get('sessionHigh'):
            continue
        near = a['hoursLeft'] <= config['releaseWindowHours']
        if a['spare'] > 0 and (near or a['spare'] >= config['releaseAnywayPercent']):
            budget[a['account']] = a['spare']
    soonest = sorted(budget, key=lambda name: next(a['hoursLeft'] for a in judged if a['account'] == name))
    queue = []
    for sink in ranked:
        want = str(sink.get('account', 'any'))
        entry = {'id': sink['id'], 'title': sink.get('title', sink['id']), 'score': score(sink),
                 'percent': cost(sink), 'needs': sink.get('needs'), 'kind': sink.get('kind'), 'released': False}
        for account in soonest:
            if want not in ('any', account) or budget[account] < cost(sink):
                continue
            budget[account] -= cost(sink)
            entry.update(released=True, account=account)
            break
        queue.append(entry)
    return queue, {name: round(left, 1) for name, left in budget.items()}


# Running.

def govern(config, now=None, fetch=None, accounts=None):
    now = now or time.time()
    tz = zone(config)
    errors = []
    if accounts is None:
        try:
            accounts = read_prometheus(config, now, fetch)
        except Exception as error:
            accounts, errors = {}, ['prometheus: %s' % error]
    judged = [judge(name, data, now, tz, config) for name, data in sorted(accounts.items())]
    sinks, sink_errors = load_sinks(config['sinks'])
    queue, left = release(sinks, judged, config)
    return {
        'generatedAt': int(now),
        'accounts': judged,
        'startOrder': start_order(judged),
        'runner': runner_ceilings(judged, config),
        'sinks': queue,
        'spareAfterSinks': left,
        'wasteTotal': round(sum(a.get('waste', 0) for a in judged), 1),
        'errors': errors + sink_errors,
        'applied': False,
    }


def when(ts, tz):
    return datetime.fromtimestamp(ts, tz).strftime('%a %H:%M') if ts else '?'


def status(state, config):
    tz = zone(config)
    lines = ['Usage governor, %s' % when(state['generatedAt'], tz)]
    for a in state['accounts']:
        if a['mode'] == 'unknown':
            lines.append('- %s: unknown (%s)' % (a['account'], a['why']))
            continue
        if a['mode'] == 'capped':
            lines.append('- %s: capped, the week is spent until %s (%.0f h)' % (
                a['account'], when(a['weeklyResetsAt'], tz), a['hoursLeft']))
            continue
        line = '- %s: %s, %.0f%% of the week, resets %s (%.0f h); lands near %.0f%% (%.0f-%.0f), floor %.0f%%, spare %.0f%%' % (
            a['account'], a['mode'], a['weekly'], when(a['weeklyResetsAt'], tz), a['hoursLeft'], a['projected'],
            a['band'][0], a['band'][1], a['floor'], a['spare'])
        if a.get('session') is not None:
            line += ', session %.0f%%' % a['session']
        if a.get('runsOutAt'):
            line += ', runs out %s' % when(a['runsOutAt'], tz)
        if a.get('readingAgeMinutes') and a['readingAgeMinutes'] > 30:
            line += ', reading %d min old' % a['readingAgeMinutes']
        lines.append(line)
    lines.append('Start new sessions on: %s' % (', '.join(state['startOrder']) or 'none has room'))
    released = [s for s in state['sinks'] if s['released']]
    if released:
        lines.append('Sinks released: %s' % ', '.join('%s on %s' % (s['id'], s['account']) for s in released))
    else:
        lines.append('Sinks released: none')
    for error in state['errors']:
        lines.append('! %s' % error)
    return '\n'.join(lines)


def write_state(state, path):
    tmp = path + '.tmp'
    with open(tmp, 'w') as f:
        json.dump(state, f, indent=1, sort_keys=True)
        f.write('\n')
    os.chmod(tmp, 0o644)
    os.replace(tmp, path)


def main(argv):
    command = argv[1] if len(argv) > 1 else 'status'
    config = load_config(os.environ.get('PULSE_GOVERNOR_CONFIG'))
    if command == 'run':
        state = govern(config)
        write_state(state, config['state'])
        print(status(state, config))
        return 0
    try:
        with open(config['state']) as f:
            state = json.load(f)
    except OSError:
        print('The governor has not run yet: %s is missing.' % config['state'], file=sys.stderr)
        return 1
    if command == 'json':
        print(json.dumps(state, indent=1, sort_keys=True))
    elif command == 'sinks':
        for s in state['sinks']:
            print('%s %-24s %5.2f %4.1f%% %s' % ('*' if s['released'] else ' ', s['id'], s['score'], s['percent'],
                                                 ('on ' + s['account']) if s['released'] else ''))
    elif command == 'status':
        print(status(state, config))
    else:
        print(__doc__, file=sys.stderr)
        return 2
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
