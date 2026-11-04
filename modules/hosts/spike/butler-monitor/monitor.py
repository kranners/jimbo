"""butler-monitor: watches Aaron's machines and resources, tells him through butler, and in act mode takes only safe steps.

One run every couple of minutes, as root on spike: collect, judge against the thresholds, choose actions, act or log what
it would do, notify, and write the status butler reads, the Machines snapshot and node_exporter's textfile.
The judging, action choice and notice wording are pure functions of a snapshot and the saved state, so the tests drive
them with fake machines.
"""

import base64
import concurrent.futures
import datetime
import grp
import json
import os
import re
import socket
import subprocess
import sys
import time
import urllib.parse
import urllib.request

CONFIG = {}
GB = 1000 ** 3
MODES = ('on', 'off', 'dry-run')


def load_config():
    with open(os.environ['MONITOR_CONFIG']) as f:
        CONFIG.update(json.load(f))


def th(name):
    return CONFIG['thresholds'][name]


# ---------------------------------------------------------------- collection

POWERSHELL_BOOT = (
    "$ProgressPreference = 'SilentlyContinue'; [Console]::OutputEncoding = [Text.Encoding]::UTF8; "
    "$script = [Console]::In.ReadToEnd(); "
    "try { & ([scriptblock]::Create($script)) } catch { [Console]::Error.WriteLine($_); exit 1 }; exit [int]$LASTEXITCODE"
)
POWERSHELL = 'powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand ' + base64.b64encode(
    POWERSHELL_BOOT.encode('utf-16-le')).decode()

KEEPAWAKE = '/etc/profiles/per-user/$USER/bin/butler-keepawake'

# Read-only reads alone: nothing here changes a setting or a file on the machine.
MAC_READ = r'''
echo "cores=$(sysctl -n hw.logicalcpu)"
echo "load=$(sysctl -n vm.loadavg | tr -d '{}')"
echo "memfree=$(memory_pressure 2> /dev/null | sed -n 's/.*free percentage: *\([0-9]*\)%.*/\1/p' | head -1)"
echo "pressure=$(sysctl -n kern.memorystatus_vm_pressure_level 2> /dev/null)"
df -k /System/Volumes/Data | awk 'NR == 2 { printf "disk_total=%.0f\ndisk_free=%.0f\n", $2 * 1024, $4 * 1024 }'
echo "power=$(pmset -g batt | sed -n "s/.*'\(.*\)'.*/\1/p" | head -1)"
echo "battery=$(pmset -g batt | grep -o '[0-9]*%' | head -1 | tr -d %)"
echo "locked=$(ioreg -n Root -d1 | grep -q 'CGSSessionScreenIsLocked"=Yes' && echo yes || echo no)"
echo "lockwhy=$(head -1 "$HOME/.local/state/butler-access/last-lock" 2> /dev/null)"
f="$HOME/.config/chromium-claude-profiles/accounts.json"
[ -r "$f" ] && [ "$(wc -c < "$f")" -lt 65536 ] && echo "claude_accounts=$(base64 < "$f" | tr -d '\n')"
k=@keepawake@
[ -x "$k" ] && echo "keepawake=$("$k" status 2> /dev/null | sed -n 's/^keep-awake: \([a-z]*\).*/\1/p' | head -1)"
'''.replace('@keepawake@', KEEPAWAKE)

LINUX_READ = r'''
echo "cores=$(nproc)"
echo "load=$(cut -d' ' -f1-3 /proc/loadavg)"
awk '/^MemTotal:/ { print "mem_total_kb=" $2 } /^MemAvailable:/ { print "mem_free_kb=" $2 }' /proc/meminfo
df -kP / | awk 'NR == 2 { printf "disk_total=%.0f\ndisk_free=%.0f\n", $2 * 1024, $4 * 1024 }'
echo "psi_full=$(sed -n 's/^full .*avg300=\([0-9.]*\).*/\1/p' /proc/pressure/memory 2> /dev/null)"
echo "locked=$(pgrep -x hyprlock > /dev/null && echo yes || echo no)"
k=@keepawake@
[ -x "$k" ] && echo "keepawake=$("$k" status 2> /dev/null | sed -n 's/^keep-awake: \([a-z]*\).*/\1/p' | head -1)"
'''.replace('@keepawake@', KEEPAWAKE)

WINDOWS_READ = r'''
$os = Get-CimInstance Win32_OperatingSystem
$cs = Get-CimInstance Win32_ComputerSystem
$c = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
"cores=$($cs.NumberOfLogicalProcessors)"
"mem_total_kb=$($os.TotalVisibleMemorySize)"
"mem_free_kb=$($os.FreePhysicalMemory)"
"disk_total=$($c.Size)"
"disk_free=$($c.FreeSpace)"
"cpu=$((Get-CimInstance Win32_Processor | Measure-Object LoadPercentage -Average).Average)"
"locked=$(if (-not $cs.UserName) { 'login' } elseif (Get-Process LogonUI -ErrorAction SilentlyContinue) { 'yes' } else { 'no' })"
$file = 'C:\ProgramData\butler-access\keepawake'
"keepawake=$(if (Test-Path $file) { (Get-Content -Raw $file).Trim() } else { 'on' })"
'''

KEEPAWAKE_ON = {
    'macos': '%s on > /dev/null && echo ok' % KEEPAWAKE,
    'linux': '%s on > /dev/null && echo ok' % KEEPAWAKE,
    'windows': r'''
$dir = 'C:\ProgramData\butler-access'
New-Item -ItemType Directory -Force $dir | Out-Null
Set-Content "$dir\keepawake" on
powercfg /change standby-timeout-ac 0
powercfg /change hibernate-timeout-ac 0
powercfg /change monitor-timeout-ac 0
'ok'
''',
}


def ssh_command(target, command, stdin=None, timeout=25):
    key = os.path.join(os.environ.get('CREDENTIALS_DIRECTORY', ''), 'butler-mac-key')
    args = [
        CONFIG['ssh'], '-i', key,
        '-o', 'IdentitiesOnly=yes', '-o', 'BatchMode=yes',
        '-o', 'StrictHostKeyChecking=accept-new',
        '-o', 'UserKnownHostsFile=' + os.path.join(CONFIG['state'], 'known_hosts'),
        '-o', 'ConnectTimeout=6', '-o', 'ControlMaster=no', '-o', 'ControlPath=none',
        '%s@%s' % (target['user'], target['address']),
        command,
    ]
    return subprocess.run(args, input=stdin, capture_output=True, text=True, timeout=timeout)


def remote(target, script, timeout=25):
    if target['os'] == 'windows':
        return ssh_command(target, POWERSHELL, stdin=script, timeout=timeout)
    return ssh_command(target, script, stdin='', timeout=timeout)


def port_open(address):
    try:
        socket.create_connection((address, 22), timeout=3).close()
        return True
    except OSError:
        return False


def resolve(name):
    entry = CONFIG['hosts'][name]
    for system in entry.get('systems', [entry]):
        if port_open(system['address']):
            return system
    return None


def parse_pairs(text):
    out = {}
    for line in (text or '').splitlines():
        if '=' in line:
            key, value = line.split('=', 1)
            out[key.strip()] = value.strip()
    return out


def num(value):
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def claude_signed_out(encoded, now=None):
    """Labels of the Claude accounts the Mac's Chromium is signed out of, from ccp's accounts.json, which holds no secrets."""
    try:
        accounts = json.loads(base64.b64decode(encoded or '')).get('accounts') or []
    except (ValueError, AttributeError):
        return []
    now = time.time() if now is None else now
    out = []
    for a in accounts if isinstance(accounts, list) else []:
        if not isinstance(a, dict) or not isinstance(a.get('label'), str):
            continue
        expires = a.get('sessionExpiresAt')
        try:
            expired = isinstance(expires, str) and datetime.datetime.fromisoformat(expires.replace('Z', '+00:00')).timestamp() <= now
        except ValueError:
            expired = False
        if a.get('state') == 'signed-out' or a.get('status') == 'revoked' or expired:
            out.append(re.sub(r'[^A-Za-z0-9 ._@-]', '', a['label'])[:64])
    return sorted(set(out))


def normalise(os_name, raw):
    """A machine's reading in one shape, whatever system it came from."""
    m = {'up': True, 'os': os_name}
    cores = num(raw.get('cores'))
    m['cores'] = int(cores) if cores else None
    loads = [num(x) for x in (raw.get('load') or '').split()]
    if len(loads) == 3 and cores:
        m['load15'] = loads[2]
        m['load_ratio'] = loads[2] / cores
    if raw.get('memfree'):
        m['mem_free_ratio'] = num(raw['memfree']) / 100 if num(raw['memfree']) is not None else None
    elif num(raw.get('mem_total_kb')):
        m['mem_free_ratio'] = num(raw.get('mem_free_kb') or 0) / num(raw['mem_total_kb'])
        m['mem_free_bytes'] = num(raw.get('mem_free_kb') or 0) * 1024
    if num(raw.get('disk_total')):
        m['disk_free_bytes'] = num(raw.get('disk_free') or 0)
        m['disk_total_bytes'] = num(raw['disk_total'])
    level = raw.get('pressure')
    if level:
        m['pressure'] = {'1': 'normal', '2': 'warn', '4': 'critical'}.get(level, 'normal')
    elif num(raw.get('psi_full')) is not None:
        m['pressure'] = 'critical' if num(raw['psi_full']) >= th('psiCritical') else 'normal'
    if raw.get('power'):
        m['on_battery'] = 'Battery' in raw['power']
        m['battery'] = num(raw.get('battery'))
    m['locked'] = raw.get('locked') if raw.get('locked') in ('yes', 'no', 'login') else None
    m['keepawake'] = raw.get('keepawake') if raw.get('keepawake') in ('on', 'off') else None
    if raw.get('claude_accounts'):
        m['claude_signed_out'] = claude_signed_out(raw['claude_accounts'])
    # butler-access's Hammerspoon watcher writes the lock's time and cause, tab-separated, and removes it on unlock.
    why = (raw.get('lockwhy') or '').split('\t')
    if m['locked'] == 'yes' and len(why) == 3:
        m['lock_at'], m['lock_cause'] = why[1], why[2]
    return m


def collect_remote(name):
    target = resolve(name)
    if target is None:
        return {'up': False, 'why': 'does not answer on ssh'}
    script = {'macos': MAC_READ, 'linux': LINUX_READ, 'windows': WINDOWS_READ}[target['os']]
    try:
        result = remote(target, script)
    except subprocess.TimeoutExpired:
        return {'up': False, 'why': 'ssh timed out'}
    if result.returncode != 0 and not result.stdout:
        return {'up': False, 'why': 'ssh failed: ' + (result.stderr.strip().splitlines() or ['exit %d' % result.returncode])[-1][:120]}
    reading = normalise(target['os'], parse_pairs(result.stdout))
    reading['address'] = target['address']
    return reading


def prom(query):
    url = CONFIG['prometheus'] + '/api/v1/query?' + urllib.parse.urlencode({'query': query})
    with urllib.request.urlopen(url, timeout=10) as response:
        body = json.load(response)
    return [(r['metric'], float(r['value'][1])) for r in body.get('data', {}).get('result', [])]


def by_host(query):
    return {metric.get('host'): value for metric, value in prom(query)}


def collect_prometheus(names):
    q = {
        'up': 'up{job="node"}',
        'mem': 'node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes',
        'mem_bytes': 'node_memory_MemAvailable_bytes',
        'load': 'avg_over_time(node_load1[15m])',
        'cores': 'count by (host) (node_cpu_seconds_total{mode="idle"})',
        'disk_free': 'node_filesystem_avail_bytes{mountpoint="/"}',
        'disk_total': 'node_filesystem_size_bytes{mountpoint="/"}',
        'swap': '1 - node_memory_SwapFree_bytes / node_memory_SwapTotal_bytes',
        'psi': 'rate(node_pressure_memory_stalled_seconds_total[5m]) * 100',
    }
    values = {key: by_host(query) for key, query in q.items()}
    out = {}
    for name in names:
        if not values['up'].get(name):
            out[name] = {'up': False, 'why': 'its node_exporter does not answer Prometheus'}
            continue
        m = {'up': True, 'os': 'linux'}
        cores = values['cores'].get(name)
        m['cores'] = int(cores) if cores else None
        if name in values['load'] and cores:
            m['load15'] = values['load'][name]
            m['load_ratio'] = values['load'][name] / cores
        if name in values['mem']:
            m['mem_free_ratio'] = values['mem'][name]
            m['mem_free_bytes'] = values['mem_bytes'].get(name)
        if name in values['disk_free'] and values['disk_total'].get(name):
            m['disk_free_bytes'] = values['disk_free'][name]
            m['disk_total_bytes'] = values['disk_total'][name]
        swap = values['swap'].get(name)
        psi = values['psi'].get(name)
        m['swap_ratio'] = swap if swap == swap else None
        m['pressure'] = 'critical' if (psi or 0) >= th('psiCritical') or (m['swap_ratio'] or 0) >= th('swapCritical') else 'normal'
        out[name] = m
    failed = [metric.get('name') for metric, value in prom('node_systemd_unit_state{state="failed",host="spike"} == 1')]
    if 'spike' in out:
        out['spike']['failed_units'] = sorted(n for n in failed if n)
    return out


def parse_size(text):
    match = re.match(r'([0-9.]+)\s*([kKMGT]?)B', text or '')
    if not match:
        return 0
    return float(match.group(1)) * {'': 1, 'k': 1e3, 'K': 1e3, 'M': 1e6, 'G': 1e9, 'T': 1e12}[match.group(2)]


def collect_spike_extras(failed, state, now):
    extras = {}
    try:
        result = subprocess.run([CONFIG['docker'], 'system', 'df', '--format', '{{json .}}'], capture_output=True, text=True, timeout=60)
        for line in result.stdout.splitlines():
            row = json.loads(line)
            if row.get('Type') == 'Build Cache':
                extras['docker_build_cache_bytes'] = parse_size(row.get('Size'))
            if row.get('Type') == 'Images':
                extras['docker_images_reclaimable_bytes'] = parse_size(row.get('Reclaimable'))
    except (OSError, subprocess.TimeoutExpired, ValueError):
        pass
    extras['units'] = collect_units(failed, state, now)
    extras['memory_cgroups'] = collect_memory_cgroups()
    try:
        extras['system_generations'] = len([n for n in os.listdir('/nix/var/nix/profiles') if re.fullmatch(r'system-[0-9]+-link', n)])
    except OSError:
        pass
    return extras


def read_limit(path):
    """A cgroup memory file's bytes, None for `max` or a file that cannot be read."""
    try:
        with open(path) as f:
            text = f.read().strip()
    except OSError:
        return None
    return int(text) if text.isdigit() else None


def collect_memory_cgroups(root='/sys/fs/cgroup', top=3):
    """spike's biggest services by memory, with their soft and hard limits, so a pressure notice arrives diagnosed."""
    out = []
    for slice_ in ('system.slice', 'user.slice'):
        try:
            names = os.listdir(os.path.join(root, slice_))
        except OSError:
            continue
        for name in names:
            path = os.path.join(root, slice_, name)
            if not name.endswith(('.service', '.slice', '.scope')) or not os.path.isdir(path):
                continue
            used = read_limit(os.path.join(path, 'memory.current'))
            if used:
                out.append({'unit': name, 'cgroup': slice_ + '/' + name, 'bytes': used,
                            'high': read_limit(os.path.join(path, 'memory.high')), 'max': read_limit(os.path.join(path, 'memory.max'))})
    return sorted(out, key=lambda c: -c['bytes'])[:top]


def biggest_memory(m):
    """The biggest memory cgroup in words, or '' when none was read."""
    groups = m.get('memory_cgroups') or []
    if not groups:
        return ''
    c = groups[0]
    cap = c.get('max') or c.get('high')
    return ' Biggest: %s at %s%s.' % (c['cgroup'], gb(c['bytes']), ' of its %s cap' % gb(cap) if cap else '')


def over_limit(m):
    """The services listed in overLimitRestart that are over their soft limit, or their hard one when they have none."""
    out = []
    for c in m.get('memory_cgroups') or []:
        if c['unit'] not in CONFIG.get('overLimitRestart', []) or c['unit'] in CONFIG['neverRestart']:
            continue
        limit = c.get('high') or c.get('max')
        if limit and c['bytes'] >= limit * 0.98:
            out.append(c)
    return out


# ---------------------------------------------------------------- failed units

# systemd's own journal messages about a unit, by MESSAGE_ID.
UNIT_RESULT = 'd9b373ed55a64feb8242e02dbe79a49c'  # Failed with result '...'.
UNIT_SUCCESS = '7ad2d189f7e94e70a38c781354912448'  # Deactivated successfully.
UNIT_STARTED = '39f53479d3a045ac8e11786248231fbf'  # Started or Finished, with JOB_RESULT.
UNIT_EXIT = '98e322203f7a4ed290d09fe03c09fe15'  # Main process exited, with EXIT_CODE and EXIT_STATUS.
# The rest of systemd's routine lines about a unit, which say nothing about why it failed.
UNIT_ROUTINE = {UNIT_RESULT, UNIT_SUCCESS, UNIT_STARTED, UNIT_EXIT,
                '7d4958e842da4a758f6c1cdc7b36dcc5', 'be02cf6855d2428ba40df7e9d022f03d', 'ae8f7b866b0347b9af31fe1c80b127c0',
                'de5b426a63be47a7b6ac3eaac82e2f6f', '9d1aaa27d60140bd96365438aad20286', '5eb03494b6584870a536b337290809b3'}
SECRETISH = re.compile(r'(gh[pousr]_|github_pat_|sk-|xox[abpr]-|glpat-)[A-Za-z0-9_-]+|[A-Za-z0-9+/_=-]{32,}')


def journal_text(value):
    if isinstance(value, list):
        return bytes(b & 0xff for b in value if isinstance(b, int)).decode('utf-8', 'replace')
    return str(value or '')


def plain_line(text):
    """One journal line fit for Aaron: its unit prefix, secrets and control characters gone, clipped."""
    text = re.sub(r'[\x00-\x1f\x7f]+', ' ', text).strip()
    text = re.sub(r'^[\w@.-]+(\.service)?: ', '', text)
    return SECRETISH.sub('…', text)[:160]


def parse_unit_journal(unit, entries):
    """A unit's last day of runs from its journal entries, oldest first: failed runs in a row, failures in the day,
    when the streak began and the last failure and recovery were, and the cause, from what the failing run logged."""
    d = {'failed_runs': 0, 'fails_day': 0, 'failed_since': None, 'last_fail': None, 'recovered_at': None,
         'cause': None, 'exit': None, 'result': None}
    lines, exit_ = [], None
    for e in entries:
        try:
            at = int(e.get('__REALTIME_TIMESTAMP')) / 1e6
        except (TypeError, ValueError):
            continue
        mid = e.get('MESSAGE_ID')
        if mid == UNIT_RESULT:
            d['failed_runs'] += 1
            d['fails_day'] += 1
            d['failed_since'] = d['failed_since'] or at
            d['last_fail'] = at
            d['result'] = e.get('UNIT_RESULT')
            d['exit'] = exit_
            # The run's own last words are the cause; failing those, systemd's own complaint.
            own = [x for x in lines if x[1]] or lines
            d['cause'] = '; '.join(dict.fromkeys(text for text, _ in own[-2:])) or None
            lines, exit_ = [], None
        elif mid == UNIT_SUCCESS or (mid == UNIT_STARTED and e.get('JOB_RESULT') == 'done'):
            if d['failed_runs']:
                d['recovered_at'] = at
            d['failed_runs'], d['failed_since'] = 0, None
            lines, exit_ = [], None
        elif mid == UNIT_EXIT:
            if e.get('EXIT_CODE') == 'exited':
                exit_ = 'exit %s' % e.get('EXIT_STATUS')
            elif e.get('EXIT_CODE'):
                exit_ = '%s by signal %s' % (e['EXIT_CODE'], e.get('EXIT_STATUS'))
        elif mid not in UNIT_ROUTINE:
            text = plain_line(journal_text(e.get('MESSAGE')))
            if text and not text.startswith(('Starting ', 'Started ', 'Finished ')):
                lines.append((text, e.get('_SYSTEMD_UNIT') == unit and e.get('_PID') != '1'))
            lines = lines[-20:]
    if d['failed_runs']:
        d['recovered_at'] = None
    return d


def run_json(args, timeout=30):
    return subprocess.run(args, capture_output=True, text=True, timeout=timeout).stdout


def journal(args):
    out = []
    for line in run_json([CONFIG['journalctl'], '--no-pager', '-o', 'json', '--output-fields',
                          'MESSAGE,MESSAGE_ID,_PID,_SYSTEMD_UNIT,UNIT,UNIT_RESULT,JOB_RESULT,EXIT_CODE,EXIT_STATUS'] + args).splitlines():
        try:
            out.append(json.loads(line))
        except ValueError:
            pass
    return out


def collect_units(failed, state, now):
    """Diagnoses every unit on spike failed now, failed since the last run, watched after a recent failure, or in
    failStreaks: its last day's runs and cause from the journal, its state, and when its timer runs it next."""
    since = state.get('last_run') or now - 300
    watch = state.setdefault('unit_watch', {})
    streaks = CONFIG.get('failStreaks', {})
    recent = set()
    try:
        recent = {e.get('UNIT') for e in journal(['--since', '@%d' % (since - 5), 'MESSAGE_ID=' + UNIT_RESULT, '_PID=1'])}
    except (OSError, subprocess.TimeoutExpired):
        pass
    names = sorted({u for u in set(failed) | recent | set(watch) | set(streaks) if u and re.fullmatch(r'[\w@:.\\-]+\.service', u)})
    timers = {}
    try:
        for t in json.loads(run_json([CONFIG['systemctl'], 'list-timers', '--all', '-o', 'json', '--no-pager']) or '[]'):
            if t.get('next'):
                timers[t.get('activates')] = t['next'] / 1e6
    except (OSError, subprocess.TimeoutExpired, ValueError, TypeError):
        pass
    units = {}
    for unit in names:
        try:
            d = parse_unit_journal(unit, journal(['-u', unit, '--since', '@%d' % (now - 86400), '-n', '3000']))
        except (OSError, subprocess.TimeoutExpired):
            d = {'unreadable': True}
        try:
            props = parse_pairs(run_json([CONFIG['systemctl'], 'show', unit, '-p', 'ActiveState', '-p', 'Result', '-p', 'InactiveExitTimestampMonotonic']))
            d['state'] = props.get('ActiveState')
            if d['state'] == 'activating' and int(props.get('InactiveExitTimestampMonotonic') or 0):
                d['running_seconds'] = time.monotonic() - int(props['InactiveExitTimestampMonotonic']) / 1e6
        except (OSError, subprocess.TimeoutExpired, ValueError):
            pass
        spec = streaks.get(unit) or {}
        if spec.get('file'):
            # A unit that counts its own failed runs, as backlogic-switch does, is believed when it counts more.
            try:
                d['failed_runs'] = max(d.get('failed_runs') or 0, int(open(spec['file']).read().strip() or 0))
            except (OSError, ValueError):
                pass
        d['next_run'] = timers.get(unit)
        units[unit] = d
        if d.get('last_fail'):
            watch[unit] = d['last_fail']
    for unit, last in list(watch.items()):
        if now - last > 86400:
            del watch[unit]
    state['last_run'] = now
    return units


def read_limits():
    usage = {}
    try:
        names = sorted(os.listdir(CONFIG['limits']))
    except OSError:
        return usage
    for name in names:
        match = re.fullmatch(r'claude-limits-([a-z0-9-]+)\.prom', name)
        if not match:
            continue
        for line in open(os.path.join(CONFIG['limits'], name)).read().splitlines():
            metric = re.match(r'claude_limit_percent\{[^}]*kind="weekly_all"[^}]*\}\s+([0-9.eE+-]+)$', line)
            if metric:
                usage[match.group(1)] = float(metric.group(1))
    return usage


def read_limit_kinds():
    """Each account's session and weekly use, in percent, from claude-limits' textfiles."""
    usage = {}
    try:
        names = sorted(os.listdir(CONFIG['limits']))
    except OSError:
        return usage
    for name in names:
        match = re.fullmatch(r'claude-limits-([a-z0-9-]+)\.prom', name)
        if not match:
            continue
        for line in open(os.path.join(CONFIG['limits'], name)).read().splitlines():
            metric = re.match(r'claude_limit_percent\{[^}]*kind="(session|weekly_all)"[^}]*\}\s+([0-9.eE+-]+)$', line)
            if metric:
                kind = 'weekly' if metric.group(1) == 'weekly_all' else 'session'
                usage.setdefault(match.group(1), {})[kind] = float(metric.group(2))
    return usage


def backoff(kinds):
    """Why butler should run fewer turns at once, or None: any account at claudeBackoffPercent of its session or week."""
    tight = ['%s %s at %.0f%%' % (account, kind, percent)
             for account, used in sorted(kinds.items()) for kind, percent in sorted(used.items())
             if percent >= th('claudeBackoffPercent')]
    return 'the Claude ' + ', '.join(tight) if tight else None


def read_turns(now):
    """The daemon's turn pool from its call state file, or None when it is missing or stale."""
    try:
        with open(CONFIG['callState']) as f:
            state = json.load(f)
    except (OSError, ValueError):
        return None
    if now - state.get('updatedAt', 0) / 1000 > 60 or not isinstance(state.get('turns'), dict):
        return None
    return state['turns']


def read_work():
    try:
        with open(CONFIG['work']) as f:
            work = json.load(f)
    except (OSError, ValueError):
        return None
    changes = work.get('changes') or []
    return {
        'running': sum(c.get('kind') in ('queued', 'working') for c in changes),
        'long': [{'id': c.get('id'), 'title': c.get('title'), 'started': c.get('started')}
                 for c in changes if c.get('kind') == 'working' and c.get('started')],
    }


def collect(state, now):
    machines = {}
    remotes = [n for n in CONFIG['hosts']]
    with concurrent.futures.ThreadPoolExecutor(max_workers=len(remotes) or 1) as pool:
        futures = {name: pool.submit(collect_remote, name) for name in remotes}
        try:
            machines.update(collect_prometheus(CONFIG['prometheusHosts']))
        except Exception as error:  # noqa: BLE001 - Prometheus down must not stop the remote checks
            for name in CONFIG['prometheusHosts']:
                machines[name] = {'up': None, 'why': 'Prometheus did not answer: %s' % str(error)[:100]}
        for name, future in futures.items():
            try:
                machines[name] = future.result(timeout=60)
            except Exception as error:  # noqa: BLE001
                machines[name] = {'up': False, 'why': str(error)[:120]}
    if machines.get('spike', {}).get('up'):
        machines['spike'].update(collect_spike_extras(machines['spike'].get('failed_units') or [], state, now))
    return {'machines': machines, 'claude': read_limits(), 'limits': read_limit_kinds(), 'work': read_work(), 'turns': read_turns(time.time())}


# ---------------------------------------------------------------- judging

def gb(value):
    return '%.0f GB' % (value / GB) if value >= 10 * GB else '%.1f GB' % (value / GB)


def finding(key, host, level, text, urgent=False, hold=0, advice='', why=None, night_note=False):
    """One problem. info is only logged and shown in the status; warn and act are told once, with the one thing to do."""
    return {'key': key, 'host': host, 'level': level, 'text': text, 'urgent': urgent, 'hold': hold,
            'advice': advice, 'why': why, 'night_note': night_note}


def quiet_down(f, why):
    """The same finding, kept to the log: Aaron is not told about it."""
    return dict(f, level='info', urgent=False, why=why)


# Findings an expectation covers: a machine meant to be off or asleep says nothing about being down, locked or awake.
EXPECTABLE = (':down', ':locked', ':keepawake', ':unknown')


def evaluate(snapshot, state, now, expected=None):
    """Every problem in this snapshot, before holds and notices are applied."""
    out = []
    expected = expected or {}
    down = state.setdefault('down_since', {})
    for host, m in sorted(snapshot['machines'].items()):
        if m.get('up') is None:
            out.append(finding('%s:unknown' % host, host, 'warn', "Couldn't read %s: %s." % (host, m.get('why', 'no answer')),
                               hold=th('unknownMinutes') * 60, advice='Check Prometheus on spike.'))
        elif not m.get('up'):
            since = down.setdefault(host, now)
            if now - since >= th('downMinutes') * 60:
                text = '%s has been unreachable since %s (%s).' % (host, time.strftime('%H:%M', time.localtime(since)), m.get('why', 'no answer'))
                if host in CONFIG['alwaysOn']:
                    out.append(finding('%s:down' % host, host, 'act', text, urgent=True, advice='Check its power and wifi.'))
                else:
                    # A laptop or the PC being off, asleep or away is ordinary; it is shown in the status, never told.
                    out.append(finding('%s:down' % host, host, 'info', text, why='a laptop or the PC being off is ordinary'))
        else:
            down.pop(host, None)
            out += judge_machine(host, m, now, snapshot.get('mode'))
    out = [dict(quiet_down(f, 'expected: ' + expected[f['host']]['reason']), expected=True)
           if f['host'] in expected and f['key'].endswith(EXPECTABLE) else f for f in out]
    claude = snapshot.get('claude') or {}
    for account, percent in sorted(claude.items()):
        if percent >= th('claudeWarnPercent'):
            out.append(finding('claude:%s' % account, 'claude', 'info', 'The %s Claude account is at %.0f%% of its week.' % (account, percent),
                               why='butler and the runner move to the next account on their own'))
    if claude and all(p >= th('claudeActPercent') for p in claude.values()):
        out.append(finding('claude:all', 'claude', 'warn', 'Every Claude account is at %.0f%% or more of its week, so Butler and the runner will stall.' % th('claudeActPercent'),
                           advice='Pause the board sessions you can spare until the weekly reset.'))
    turns = snapshot.get('turns')
    if turns:
        oldest = turns.get('oldestQueuedAt')
        if oldest and now - oldest / 1000 >= th('turnQueueWarnSeconds'):
            waited = now - oldest / 1000
            stuck = waited >= th('turnStuckMinutes') * 60
            out.append(finding('butler:queue', 'spike', 'warn' if stuck else 'info',
                               "A Butler turn has waited %s for a free slot (%d running, %d waiting)." % (
                                   duration(waited), turns.get('running', 0), turns.get('queued', 0)),
                               advice='Say /restart in my DM, or stop a long board turn.', why=None if stuck else 'queued, not stuck'))
        full = turns.get('fullSince')
        if full and now - full / 1000 >= th('turnSlotsBusyMinutes') * 60:
            out.append(finding('butler:slots', 'spike', 'info',
                               "All %d of Butler's turn slots have been busy for %s." % (turns.get('cap', 0), duration(now - full / 1000)),
                               why='busy is not stuck; a stuck turn is told'))
    work = snapshot.get('work')
    if work:
        if work['running'] > th('maxRunningChanges'):
            out.append(finding('work:running', 'spike', 'info', '%d changes are running at once.' % work['running'], why='his own requests'))
        for change in work['long']:
            if now - change['started'] > th('maxChangeHours') * 3600:
                out.append(finding('work:long:%s' % change['id'], 'spike', 'warn',
                                   'The change "%s" has been running for %s.' % (change['title'], duration(now - change['started'])),
                                   advice='Look at it on the Work tab, or archive it.'))
    return out


def judge_machine(host, m, now=None, mode=None):
    out = []
    mac = m.get('os') == 'macos'
    free, total = m.get('disk_free_bytes'), m.get('disk_total_bytes')
    if free is not None and total:
        ratio = free / total
        text = "%s's disk has %s free (%.0f%%)." % (host, gb(free), ratio * 100)
        if ratio < th('diskActRatio') or free < th('diskActGB') * GB:
            out.append(finding('%s:disk' % host, host, 'act', text, urgent=True, advice='Free some space on it soon.'))
        elif ratio < th('diskWarnRatio') or free < th('diskWarnGB') * GB:
            out.append(finding('%s:disk' % host, host, 'warn', text, advice='Free some space on it when you can.'))
    mem = m.get('mem_free_ratio')
    if mem is not None:
        text = '%s has %.0f%% of its memory free.' % (host, mem * 100)
        # macOS keeps its memory full by design, so a Mac is judged by its memory pressure alone.
        if mac:
            if mem < th('memWarnRatio'):
                out.append(finding('%s:memory' % host, host, 'info', text, why='a Mac is judged by memory pressure'))
        else:
            text += biggest_memory(m)
            if mem < th('memActRatio'):
                out.append(finding('%s:memory' % host, host, 'act', text, urgent=host in CONFIG['alwaysOn'], hold=th('memActMinutes') * 60,
                                   advice='Stop something big on it before the OOM killer does.'))
            if mem < th('memWarnRatio'):
                out.append(finding('%s:memory' % host, host, 'warn', text, advice='Check what is using its memory.'))
    if m.get('pressure') == 'critical':
        # Told only once it has lasted pressureMinutes; restarting an over-limit service is told at once, as an action.
        out.append(finding('%s:pressure' % host, host, 'act', '%s is under critical memory pressure.%s' % (host, biggest_memory(m)),
                           urgent=host in CONFIG['alwaysOn'], hold=th('pressureMinutes') * 60,
                           advice='Close or stop something big on it.'))
    ratio = m.get('load_ratio') or 0
    if ratio > th('loadNoteRatio'):
        text = "%s's load has averaged %.1f over 15 minutes on %d cores." % (host, m['load15'], m['cores'])
        out.append(finding('%s:load' % host, host, 'info', text, why='busy, under %gx its cores' % th('loadRatio')))
        if ratio > th('loadRatio'):
            out.append(finding('%s:load' % host, host, 'warn', text, hold=th('loadMinutes') * 60,
                               advice='Something on it may be runaway; check its busiest process.'))
    awake = m.get('keepawake')
    if m.get('on_battery') and awake == 'on' and m.get('battery') is not None:
        text = '%s is on battery at %.0f%% with keep-awake on.' % (host, m['battery'])
        if m['battery'] < th('batteryActPercent'):
            out.append(finding('%s:battery' % host, host, 'act', text, advice='Plug it in.'))
        elif m['battery'] < th('batteryWarnPercent'):
            out.append(finding('%s:battery' % host, host, 'warn', text, advice='Plug it in.'))
    if awake == 'on' and m.get('locked') == 'yes' and mac:
        # At night a locked Mac is only a line in the morning summary.
        out.append(finding('%s:locked' % host, host, 'warn', "%s's screen is locked though keep-awake is on: %s." % (host, lock_reason(m)),
                           advice='Unlock it when you want me to drive it.', night_note=True))
    if awake == 'off' and host in CONFIG['keepAwakeHosts']:
        out.append(finding('%s:keepawake' % host, host, 'act', "%s's keep-awake is off." % host,
                           advice='Ask me to turn it back on, or tell me it is meant to be off.'))
    # ccp's Claude Profiles extension writes each saved Claude account's state; only a real sign-out is news.
    for label in m.get('claude_signed_out') or []:
        out.append(finding('%s:claude-account:%s' % (host, label), host, 'warn',
                           "%s's Chromium is signed out of the Claude account %s." % (host, label),
                           advice='Sign it back in once: Claude Profiles popup, Sign back in to signed-out accounts, or sign in and Save current.'))
    out += judge_units(host, m, now, mode)
    if m.get('docker_build_cache_bytes', 0) > th('dockerCacheGB') * GB:
        out.append(finding('spike:docker', host, 'info', "Docker's build cache on spike holds %s." % gb(m['docker_build_cache_bytes']),
                           why='docker-prune clears it daily'))
    if m.get('system_generations', 0) > th('maxGenerations'):
        out.append(finding('spike:generations', host, 'warn', 'spike keeps %d system generations.' % m['system_generations'],
                           advice='Pruning has stopped; ask for a change to look at it.'))
    return out


def hm(at):
    return time.strftime('%H:%M', time.localtime(at))


def when(at, now):
    """A time of day, with the day when it is not today."""
    if time.strftime('%Y-%m-%d', time.localtime(at)) == time.strftime('%Y-%m-%d', time.localtime(now)):
        return hm(at)
    return time.strftime('%a %H:%M', time.localtime(at))


def unit_name(unit):
    return unit[:-len('.service')] if unit.endswith('.service') else unit


def unit_cause(d):
    """Why it failed, in plain words, from what it logged and how it ended."""
    cause = d.get('cause') or 'it logged nothing before failing'
    how = d.get('exit') or ''
    if d.get('result') == 'timeout':
        how = 'it ran past its time limit'
    elif d.get('exit') == 'exit 243' or 'credential' in cause.lower():
        how = 'a secret file it loads is missing'
    elif d.get('exit') == 'exit 78':
        how = 'it says a setting or token it needs is missing'
    elif 'No space left' in cause:
        how = "spike's disk is full"
    return cause + (' (%s)' % how if how else '')


def unit_next(unit, d, mode, now):
    """What happens next, or the one thing Aaron must do."""
    if re.fullmatch(CONFIG['restartable'], unit) and unit not in CONFIG['neverRestart'] and d.get('state') == 'failed':
        if mode == 'on':
            return "I'm restarting it once now, and if that doesn't hold, say \"fix it\" and I'll start a change on it."
        return "I'd restart it once, but my acting is in dry-run, so say \"fix it\" and I'll start a change on it."
    if d.get('next_run') and d['next_run'] > now:
        return 'Its timer tries again at %s; say "fix it" and I\'ll start a change on it.' % hm(d['next_run'])
    return 'Nothing retries it by itself; say "fix it" and I\'ll start a change on it.'


def judge_units(host, m, now, mode):
    """Every failed unit arrives investigated: a failure that healed itself, or is still under the bar, is only logged
    with its cause; repeated, lasting or frequent failures are told with the cause, its state and what happens next."""
    out = []
    now = time.time() if now is None else now
    streaks = CONFIG.get('failStreaks', {})
    units = m.get('units') or {}
    failed_now = set(m.get('failed_units') or [])
    for unit in sorted(failed_now | set(units)):
        d = units.get(unit)
        key = '%s:failed:%s' % (host, unit)
        name = unit_name(unit)
        if d is None or d.get('unreadable'):
            if unit in failed_now:
                out.append(finding(key, host, 'warn', "%s has failed on %s, and I couldn't read its journal to see why." % (name, host),
                                   advice='Say "fix it" and I\'ll start a change on it.'))
            continue
        spec = streaks.get(unit) or {}
        runs_bar = spec.get('runs', th('unitFailRuns'))
        is_failed = d.get('state') == 'failed' if d.get('state') else unit in failed_now
        runs, day = d.get('failed_runs') or 0, d.get('fails_day') or 0
        since = d.get('failed_since')
        cause = unit_cause(d)
        if runs:
            lasting = is_failed and since and now - since >= th('unitFailedMinutes') * 60
            if runs >= runs_bar or lasting or day >= th('unitFailsPerDay'):
                if runs >= runs_bar and runs > 1:
                    head = 'has failed %d runs in a row since %s' % (runs, when(since, now))
                elif lasting:
                    head = 'has been down since %s' % when(since, now)
                else:
                    head = 'has failed %d times in the last day, last at %s' % (day, when(d['last_fail'], now))
                if is_failed:
                    state_line = 'It is still down.'
                elif d.get('state') == 'activating':
                    state_line = 'Its next run is going now.'
                else:
                    state_line = 'It runs again at %s.' % hm(d['next_run']) if d.get('next_run') and d['next_run'] > now else ''
                out.append(finding(key, host, 'warn', ('%s on %s %s: %s. %s' % (name, host, head, cause, state_line)).strip(),
                                   advice=unit_next(unit, d, mode, now)))
            else:
                out.append(finding(key, host, 'info', '%s on %s failed at %s: %s.' % (name, host, when(d['last_fail'], now), cause),
                                   why='%s; it is told after %d in a row or %d minutes down' % (
                                       'one failed run' if runs == 1 else '%d failed runs' % runs, runs_bar, th('unitFailedMinutes'))))
        elif d.get('last_fail') and now - d['last_fail'] < 86400:
            if day >= th('unitFailsPerDay'):
                out.append(finding(key, host, 'warn', '%s on %s has failed %d times in the last day, last at %s: %s. It recovered by itself each time, last at %s, but keeps failing.' % (
                    name, host, day, when(d['last_fail'], now), cause, when(d['recovered_at'], now) if d.get('recovered_at') else 'its next run'),
                    advice='Say "fix it" and I\'ll start a change on it.'))
            else:
                out.append(finding(key, host, 'info', '%s on %s failed at %s: %s.' % (name, host, when(d['last_fail'], now), cause),
                                   why='recovered by itself at %s' % when(d['recovered_at'], now) if d.get('recovered_at') else 'recovered by itself'))
        elif is_failed:
            out.append(finding(key, host, 'warn', '%s on %s has been down for over a day, and its journal for the last day does not say why.' % (name, host),
                               advice=unit_next(unit, d, mode, now)))
        running = d.get('running_seconds')
        if spec.get('stuckMinutes') and running is not None and running >= spec['stuckMinutes'] * 60:
            out.append(finding('%s:stuck:%s' % (host, unit), host, 'warn',
                               '%s on %s has been running for %d minutes without finishing.' % (name, host, running // 60),
                               advice="If it's still going in another 10 minutes, say \"fix it\" and I'll start a change on it."))
    return out


def lock_reason(m):
    if m.get('lock_cause'):
        return 'it locked at %s, and %s' % (m['lock_at'], m['lock_cause'])
    return 'no lock was recorded, so it locked while the lock watcher was not running, and only Aaron can unlock it'


def settle(findings, state, now):
    """Applies holds, so a level counts only once it has lasted, and keeps one finding per key, the worst."""
    since = state.setdefault('since', {})
    seen, out = set(), {}
    for f in findings:
        ident = f['key'] + '/' + f['level']
        seen.add(ident)
        first = since.setdefault(ident, now)
        if f['hold'] and now - first < f['hold']:
            continue
        current = out.get(f['key'])
        if current is None or rank(f['level']) > rank(current['level']):
            out[f['key']] = f
    for ident in list(since):
        if ident not in seen:
            del since[ident]
    return list(out.values())


def rank(level):
    return {'info': 0, 'warn': 1, 'act': 2}[level]


def duration(seconds):
    minutes = int(seconds // 60)
    if minutes < 60:
        return '%d minutes' % minutes
    hours = minutes // 60
    return '%d hour%s' % (hours, '' if hours == 1 else 's') if hours < 48 else '%d days' % (hours // 24)


# ---------------------------------------------------------------- actions

SPIKE_DISK_ACTIONS = ['clean-outbox', 'journal-vacuum', 'docker-prune', 'gc-generations']


def choose_actions(findings, snapshot):
    """The safe actions these findings call for, by (name, host). Nothing outside this table is ever done."""
    actions = []
    keys = {f['key']: f for f in findings}
    spike = snapshot['machines'].get('spike') or {}
    if keys.get('spike:disk', {}).get('level') == 'act':
        actions += [(name, 'spike') for name in SPIKE_DISK_ACTIONS]
    elif 'spike:docker' in keys:
        actions.append(('docker-prune', 'spike'))
    for f in findings:
        if f.get('expected'):
            continue
        if f['key'].endswith(':keepawake') and f['host'] in CONFIG['keepAwakeHosts'] and f['host'] not in CONFIG['readOnlyHosts']:
            actions.append(('keepawake-on', f['host']))
        if f['key'].endswith(':locked') and f['host'] in CONFIG['keepAwakeHosts'] and f['host'] not in CONFIG['readOnlyHosts']:
            actions.append(('keepawake-reassert', f['host']))
    for unit in spike.get('failed_units') or []:
        # Only a failure Aaron is told about is worth a restart; one that heals itself is left to its timer.
        if keys.get('spike:failed:' + unit, {}).get('level', 'info') == 'info':
            continue
        if re.fullmatch(CONFIG['restartable'], unit) and unit not in CONFIG['neverRestart']:
            actions.append(('restart:' + unit, 'spike'))
    # Raw pressure, not the settled finding, so a runaway listed service is restarted before the notice's hold ends.
    if spike.get('pressure') == 'critical':
        actions += [('limit-restart:' + c['unit'], 'spike') for c in over_limit(spike)]
    tight = any(f['level'] == 'act' and (f['key'].startswith('claude:') or f['host'] == 'spike') for f in findings)
    actions.append(('hold-work' if tight else 'release-work', 'spike'))
    return actions


def describe(name, host):
    if name.startswith('restart:'):
        return 'restart %s on spike once' % name.split(':', 1)[1]
    if name.startswith('limit-restart:'):
        return 'restart %s on spike, which was over its memory limit under critical pressure' % name.split(':', 1)[1]
    return {
        'clean-outbox': "delete butler's own outbox pictures older than 2 days and spike's aged temp files",
        'journal-vacuum': "shrink spike's journal to %s" % CONFIG['journalVacuum'],
        'docker-prune': "clear Docker's build cache and dangling images on spike",
        'gc-generations': 'collect Nix garbage on spike, keeping the newest %d system generations' % CONFIG['keepGenerations'],
        'keepawake-on': "turn %s's keep-awake back on" % host,
        'keepawake-reassert': "restart %s's keep-awake agent, so its caffeinate holds again; it cannot unlock the screen" % host,
        'hold-work': 'hold new change sessions and runner launches while resources are tight',
        'release-work': 'release the hold on new change sessions and runner launches',
    }[name]


def disk_free():
    s = os.statvfs('/')
    return s.f_bavail * s.f_frsize


def run_local(args, timeout=900):
    result = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
    if result.returncode != 0:
        raise RuntimeError((result.stderr.strip().splitlines() or ['exit %d' % result.returncode])[-1][:160])


def do_action(name, host):
    """Does one action and returns its (before, after) reading."""
    if name in ('keepawake-on', 'keepawake-reassert'):
        target = resolve(host)
        if target is None:
            raise RuntimeError('%s did not answer' % host)
        result = remote(target, KEEPAWAKE_ON[target['os']], timeout=40)
        if 'ok' not in result.stdout:
            raise RuntimeError((result.stderr.strip() or 'no ok')[:160])
        return ('off', 'on') if name == 'keepawake-on' else ('locked', 'reasserted, still locked')
    if name in ('hold-work', 'release-work'):
        hold = CONFIG['holdFile']
        before = 'held' if os.path.exists(hold) else 'free'
        if name == 'hold-work':
            write_file(hold, 'Held by butler-monitor at %s\n' % time.strftime('%Y-%m-%d %H:%M'), 0o640)
        elif os.path.exists(hold):
            os.unlink(hold)
        return before, 'held' if name == 'hold-work' else 'free'
    before = disk_free()
    if name == 'clean-outbox':
        run_local(['find', CONFIG['outbox'], '-xdev', '-type', 'f', '-mtime', '+2', '-delete'])
        run_local([CONFIG['tmpfiles'], '--clean'])
    elif name == 'journal-vacuum':
        run_local([CONFIG['journalctl'], '--vacuum-size=' + CONFIG['journalVacuum']])
    elif name == 'docker-prune':
        run_local([CONFIG['docker'], 'builder', 'prune', '--force'])
        run_local([CONFIG['docker'], 'image', 'prune', '--force'])
    elif name == 'gc-generations':
        run_local([CONFIG['nixEnv'], '--profile', '/nix/var/nix/profiles/system', '--delete-generations', '+%d' % CONFIG['keepGenerations']])
        run_local([CONFIG['nixStore'], '--gc'], timeout=1800)
    elif name.startswith('limit-restart:'):
        unit = name.split(':', 1)[1]
        cgroup = '/sys/fs/cgroup/system.slice/' + unit
        before = read_limit(cgroup + '/memory.current') or 0
        run_local([CONFIG['systemctl'], 'restart', unit], timeout=120)
        return gb(before) + ' used', gb(read_limit(cgroup + '/memory.current') or 0) + ' used'
    elif name.startswith('restart:'):
        run_local([CONFIG['systemctl'], 'restart', name.split(':', 1)[1]], timeout=120)
        return 'failed', subprocess.run([CONFIG['systemctl'], 'is-active', name.split(':', 1)[1]], capture_output=True, text=True).stdout.strip()
    else:
        raise RuntimeError('not a known action')
    return gb(before) + ' free', gb(disk_free()) + ' free'


def act(actions, state, mode, now, doer=do_action):
    """Runs or logs each action, at most once an hour per action and machine; returns the outcome lines."""
    last = state.setdefault('acted', {})
    results = []
    held_key = 'held' if mode == 'on' else 'dry_held'
    for name, host in actions:
        ident = '%s@%s/%s' % (name, host, mode)
        if name in ('hold-work', 'release-work'):
            held = state.get(held_key, False)
            if (name == 'hold-work') == held:
                continue
        elif ident in last and now - last[ident] < (th('overLimitRestartMinutes') * 60 if name.startswith('limit-restart:') else 3600):
            continue
        if name.startswith('restart:') and name in state.setdefault('restarted', {}):
            continue
        entry = {'at': int(now), 'action': name, 'host': host, 'mode': mode, 'what': describe(name, host)}
        if mode == 'off':
            continue
        if mode == 'dry-run':
            entry['result'] = 'dry-run'
            line = 'Would %s (acting is in dry-run).' % entry['what']
            if name in ('hold-work', 'release-work'):
                state[held_key] = name == 'hold-work'
        else:
            try:
                before, after = doer(name, host)
                entry.update(result='done', before=before, after=after)
                line = 'Did: %s, %s → %s.' % (entry['what'], before, after)
            except Exception as error:  # noqa: BLE001
                entry.update(result='failed', error=str(error)[:200])
                line = 'Tried to %s, but it failed: %s.' % (entry['what'], str(error)[:120])
            if name in ('hold-work', 'release-work'):
                state['held'] = name == 'hold-work'
            if name.startswith('restart:'):
                state['restarted'][name] = int(now)
        last[ident] = now
        entry['line'] = line[0].upper() + line[1:]
        results.append(entry)
    # A unit that recovered may be restarted again the next time it fails.
    failing = {name for name, _ in actions if name.startswith('restart:')}
    for name in list(state.get('restarted', {})):
        if name not in failing:
            del state['restarted'][name]
    return results


# ---------------------------------------------------------------- notices

def in_quiet(local):
    start, end = CONFIG['quiet']['start'], CONFIG['quiet']['end']
    hm = '%02d:%02d' % (local.tm_hour, local.tm_min)
    return hm >= start or hm < end if start > end else start <= hm < end


def told(f, prefix=''):
    return prefix + ('⚠️ ' if f['level'] == 'act' else '') + f['text'] + (' ' + f['advice'] if f.get('advice') else '')


def log_entry(now, f, route, why=None):
    return {'at': int(now), 'key': f['key'], 'host': f['host'], 'level': f['level'], 'text': f['text'], 'route': route,
            'why': why if why is not None else f.get('why')}


def notices(findings, results, state, now, local, unreadable=()):
    """What to tell Aaron now: (dm lines, shout line or None, log entries).

    A problem is told once, when it is new, and again only when it gets worse, or once as still open after
    stillOpenHours. Everything else, info findings, problems already told, dry-run plans and resolutions, only goes
    to the log, written whenever a problem's route changes, so `monitor log` shows what was seen and not told.
    """
    sent = state.setdefault('sent', {})
    routes = state.setdefault('routes', {})
    quiet = in_quiet(local)
    overnight = state.setdefault('overnight', [])
    out, urgent, log = [], [], []
    present, seen_info = set(), set()

    def route(f, name, why=None):
        mark = '%s/%s/%s' % (f['level'], name, why or f.get('why') or '')
        if routes.get(f['key']) != mark:
            routes[f['key']] = mark
            log.append(log_entry(now, f, name, why))

    for f in findings:
        if f['level'] == 'info':
            route(f, 'kept')
            seen_info.add(f['key'])
            continue
        present.add(f['key'])
        previous = sent.get(f['key'])
        if previous is None:
            reason, text = 'new', told(f)
        elif rank(f['level']) > rank(previous['level']):
            reason, text = 'worse', told(f, 'Worse: ')
        elif not previous.get('reraised') and now - previous['at'] >= th('stillOpenHours') * 3600:
            reason, text = 'still open', told(f, 'Still open after %s: ' % duration(now - previous.get('first', previous['at'])))
        else:
            previous.pop('gone', None)
            route(f, 'kept', 'already told')
            continue
        sent[f['key']] = {'first': (previous or {}).get('first', (previous or {}).get('at', now)), 'at': now,
                          'level': f['level'], 'text': f['text'], 'reraised': reason == 'still open'}
        if quiet and not f['urgent']:
            overnight.append({'key': f['key'], 'text': f['text'] if f.get('night_note') else text})
            route(f, 'noted for the morning' if f.get('night_note') else 'held for the morning', reason)
        else:
            out.append(text)
            route(f, 'told', reason)
            if f['urgent']:
                urgent.append(f['text'])
    for key, entry in list(sent.items()):
        if key in present:
            continue
        # A machine that is down says nothing about its disk or memory, and a problem must be gone a while to count.
        if key.split(':', 1)[0] in unreadable and not key.endswith((':down', ':unknown')):
            continue
        gone = entry.setdefault('gone', now)
        if now - gone >= th('clearMinutes') * 60:
            del sent[key]
            routes.pop(key, None)
            log.append({'at': int(now), 'key': key, 'host': key.split(':', 1)[0], 'level': entry['level'],
                        'text': entry['text'], 'route': 'cleared', 'why': 'gone for %d minutes' % th('clearMinutes')})
    # A quiet finding that went away is logged afresh when it comes back, such as a unit failing again next week.
    for key in list(routes):
        if key not in present and key not in seen_info and key not in sent:
            del routes[key]
    for r in results:
        # Only what the monitor really did is news; a dry-run plan is logged, and the hold flag is housekeeping.
        if r['result'] == 'dry-run' or r['action'] in ('hold-work', 'release-work'):
            continue
        if quiet:
            overnight.append({'key': 'action', 'text': r['line']})
        else:
            out.append(r['line'])
    shout = None
    if urgent:
        shout = 'Monitor: ' + urgent[0]
        if len(urgent) > 1:
            shout += ' And %d more in Discord.' % (len(urgent) - 1)
        shout = shout[:200]
    return out, shout, log


def morning(state, local, findings):
    """One short list after quiet hours, only when something was held or done overnight."""
    today = time.strftime('%Y-%m-%d', local)
    hm = '%02d:%02d' % (local.tm_hour, local.tm_min)
    if hm < CONFIG['quiet']['summary'] or in_quiet(local) or state.get('summary_date') == today:
        return None
    state['summary_date'] = today
    overnight = state.pop('overnight', [])
    if not overnight:
        return None
    still = {f['key'] for f in findings if f['level'] != 'info'}
    lines = []
    for item in overnight[-10:]:
        item = item if isinstance(item, dict) else {'key': 'action', 'text': item}
        gone = item['key'] != 'action' and item['key'] not in still
        lines.append('- ' + item['text'] + (' (since cleared)' if gone else ''))
    return 'Overnight, machines:\n' + '\n'.join(lines)


# ---------------------------------------------------------------- expectations

def parse_expect(args, now, local=None):
    """`<host> [down|asleep] [until HH:MM | for <N>h|<N>m] [reason...]` as (host, until, reason)."""
    if not args:
        raise ValueError('expect takes a machine')
    host, rest = args[0], list(args[1:])
    if host not in known_hosts():
        raise ValueError('%s is not a machine the monitor watches: %s' % (host, ', '.join(sorted(known_hosts()))))
    if rest[:1] in (['down'], ['asleep'], ['off']):
        rest = rest[1:]
    until = now + 12 * 3600
    if rest[:1] == ['until'] and len(rest) >= 2:
        match = re.fullmatch(r'([01]?[0-9]|2[0-3]):([0-5][0-9])', rest[1])
        if not match:
            raise ValueError('until takes HH:MM')
        local = local or time.localtime(now)
        midnight = now - (local.tm_hour * 3600 + local.tm_min * 60 + local.tm_sec)
        until = midnight + int(match.group(1)) * 3600 + int(match.group(2)) * 60
        if until <= now:
            until += 86400
        rest = rest[2:]
    elif rest[:1] == ['for'] and len(rest) >= 2:
        match = re.fullmatch(r'([0-9]{1,3})([hm])', rest[1])
        if not match:
            raise ValueError('for takes a number of hours or minutes, such as 3h or 45m')
        until = now + int(match.group(1)) * (3600 if match.group(2) == 'h' else 60)
        rest = rest[2:]
    reason = ' '.join(rest).strip() or 'switched off on purpose'
    return host, min(until, now + 7 * 86400), re.sub(r'[^\w .,:;()/\'-]', '', reason)[:120]


def known_hosts():
    return set(CONFIG['hosts']) | set(CONFIG['prometheusHosts'])


def expect_path(host):
    return os.path.join(CONFIG['expected'], host + '.json')


def write_expect(host, until, reason, now, by='aaron'):
    os.makedirs(CONFIG['expected'], exist_ok=True)
    tmp = expect_path(host) + '.tmp'
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NOFOLLOW, 0o660)
    with os.fdopen(fd, 'w') as f:
        json.dump({'host': host, 'until': int(until), 'reason': reason, 'set': int(now), 'by': by}, f)
    os.replace(tmp, expect_path(host))


def read_expected(now):
    """Each machine's live expectation, read without following links, since butler writes the directory."""
    out = {}
    try:
        names = os.listdir(CONFIG['expected'])
    except OSError:
        return out
    for name in names:
        host = name[:-5] if name.endswith('.json') else None
        if host not in known_hosts():
            continue
        try:
            fd = os.open(expect_path(host), os.O_RDONLY | os.O_NOFOLLOW)
            with os.fdopen(fd) as f:
                entry = json.loads(f.read(4096))
            until, set_at = float(entry['until']), float(entry.get('set', now))
        except (OSError, ValueError, KeyError, TypeError):
            continue
        if until > now:
            out[host] = {'until': until, 'set': set_at, 'by': str(entry.get('by', ''))[:20],
                         'reason': str(entry.get('reason') or 'switched off on purpose')[:120]}
        else:
            drop_expect(host)
    return out


def drop_expect(host):
    try:
        os.unlink(expect_path(host))
    except OSError:
        pass


def settle_expected(expected, snapshot, now):
    """Ends an expectation early once its machine is back, awake and unlocked, at least 10 minutes after it was set."""
    ended = []
    for host, entry in list(expected.items()):
        m = snapshot['machines'].get(host) or {}
        if m.get('up') and m.get('locked') != 'yes' and m.get('keepawake') != 'off' and now - entry['set'] >= 600:
            del expected[host]
            ended.append(host)
    return ended


def expected_text(expected):
    if not expected:
        return 'No machine is expected off.'
    return '\n'.join('%s is expected off until %s: %s.' % (host, time.strftime('%a %H:%M', time.localtime(e['until'])), e['reason'])
                     for host, e in sorted(expected.items()))


# ---------------------------------------------------------------- output

def write_file(path, text, mode=0o640):
    tmp = path + '.tmp'
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NOFOLLOW, mode)
    with os.fdopen(fd, 'w') as f:
        f.write(text)
    os.chmod(tmp, mode)
    if CONFIG.get('group') and mode & 0o040:
        try:
            os.chown(tmp, -1, grp.getgrnam(CONFIG['group']).gr_gid)
        except (KeyError, OSError):
            pass
    os.replace(tmp, path)


def read_mode():
    path = CONFIG['control']
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
        with os.fdopen(fd) as f:
            value = f.read(32).strip()
    except OSError:
        return CONFIG['defaultMode']
    return value if value in MODES else CONFIG['defaultMode']


def machine_line(host, m):
    if m.get('up') is None:
        return '%s: not read (%s)' % (host, m.get('why'))
    if not m.get('up'):
        return '%s: down (%s)' % (host, m.get('why'))
    parts = []
    if m.get('mem_free_ratio') is not None:
        parts.append('memory %.0f%% free' % (m['mem_free_ratio'] * 100))
    if m.get('disk_free_bytes') is not None:
        parts.append('disk %s free' % gb(m['disk_free_bytes']))
    if m.get('load15') is not None:
        parts.append('load %.1f on %d cores' % (m['load15'], m['cores']))
    if m.get('on_battery') is not None:
        parts.append(('battery %.0f%%' % m['battery']) if m['on_battery'] else 'on AC')
    if m.get('keepawake'):
        parts.append('keep-awake ' + m['keepawake'])
    if m.get('locked') == 'yes':
        parts.append('locked')
    return '%s: up, %s' % (host, ', '.join(parts) or 'no readings')


def status_text(snapshot, findings, mode, now, expected=None):
    lines = ['Monitor checked at %s; acting is %s.' % (time.strftime('%H:%M', time.localtime(now)), mode)]
    lines += [machine_line(h, m) for h, m in sorted(snapshot['machines'].items())]
    for account, percent in sorted((snapshot.get('claude') or {}).items()):
        lines.append('Claude %s: %.0f%% of the week' % (account, percent))
    turns = snapshot.get('turns')
    if turns:
        lines.append('Butler turns: %d running of %d, %d waiting%s' % (
            turns.get('running', 0), turns.get('cap', 0), turns.get('queued', 0),
            ', backing off while %s' % turns['backoff'] if turns.get('backoff') else ''))
    problems = [f['text'] for f in findings if f['level'] != 'info']
    noted = [f['text'] + (' (%s)' % f['why'] if f.get('why') else '') for f in findings if f['level'] == 'info']
    lines.append('Open problems: ' + ('; '.join(problems) if problems else 'none'))
    if noted:
        lines.append('Seen, not worth telling Aaron: ' + '; '.join(noted))
    lines.append(expected_text(expected or {}))
    return '\n'.join(lines) + '\n'


def prom_lines(snapshot, findings, mode, now):
    out = ['butler_monitor_last_run_timestamp_seconds %d' % now]
    for m_name in MODES:
        out.append('butler_monitor_mode{mode="%s"} %d' % (m_name, mode == m_name))
    metrics = {
        'host_up': lambda m: 1 if m.get('up') else 0,
        'memory_free_ratio': lambda m: m.get('mem_free_ratio'),
        'disk_free_bytes': lambda m: m.get('disk_free_bytes'),
        'disk_free_ratio': lambda m: m['disk_free_bytes'] / m['disk_total_bytes'] if m.get('disk_total_bytes') else None,
        'load_ratio': lambda m: m.get('load_ratio'),
        'battery_percent': lambda m: m.get('battery'),
        'on_battery': lambda m: None if m.get('on_battery') is None else int(m['on_battery']),
        'keepawake': lambda m: None if m.get('keepawake') is None else int(m['keepawake'] == 'on'),
        'locked': lambda m: None if m.get('locked') is None else int(m['locked'] == 'yes'),
    }
    for metric, get in metrics.items():
        for host, m in sorted(snapshot['machines'].items()):
            value = get(m)
            if value is not None:
                out.append('butler_monitor_%s{machine="%s"} %s' % (metric, host, repr(float(value))))
    turns = snapshot.get('turns')
    if turns:
        oldest, full = turns.get('oldestQueuedAt'), turns.get('fullSince')
        out += [
            'butler_turns_running %d' % turns.get('running', 0),
            'butler_turns_queued %d' % turns.get('queued', 0),
            'butler_turns_lane{lane="interactive"} %d' % turns.get('interactive', 0),
            'butler_turns_lane{lane="background"} %d' % turns.get('background', 0),
            'butler_turns_cap %d' % turns.get('cap', 0),
            'butler_turns_backoff %d' % (1 if turns.get('backoff') else 0),
            'butler_turns_oldest_queued_seconds %d' % (max(0, now - oldest / 1000) if oldest else 0),
            'butler_turns_slots_busy_seconds %d' % (max(0, now - full / 1000) if full else 0),
        ]
    for level in ('info', 'warn', 'act'):
        out.append('butler_monitor_findings{level="%s"} %d' % (level, sum(f['level'] == level for f in findings)))
    return '\n'.join(out) + '\n'


def send(lines, shout):
    if lines:
        text = 'Machines: ' + lines[0] if len(lines) == 1 else 'Machines:\n' + '\n'.join('- ' + x for x in lines)
        subprocess.run([CONFIG['notify']], input=text[:1900], text=True, capture_output=True, timeout=30)
    if shout:
        subprocess.run([CONFIG['callSay'], '--urgent', '--call-only'], input=shout, text=True, capture_output=True, timeout=30)


def load_state():
    try:
        with open(os.path.join(CONFIG['state'], 'state.json')) as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def append_log(entries):
    """The notice log `monitor log` reads: everything seen and what became of it, cut back by half past 2 MB."""
    path = os.path.join(CONFIG['state'], 'notices.jsonl')
    if not entries:
        return
    with open(path, 'a') as log:
        for entry in entries:
            log.write(json.dumps(entry, ensure_ascii=False) + '\n')
    if os.path.getsize(path) > 2 * 1000 ** 2:
        with open(path) as f:
            kept = f.readlines()
        write_file(path, ''.join(kept[len(kept) // 2:]), 0o640)
    else:
        os.chmod(path, 0o640)


def run():
    now = time.time()
    local = time.localtime(now)
    state = load_state()
    mode = read_mode()
    snapshot = collect(state, now)
    snapshot['mode'] = mode
    expected = read_expected(now)
    entries = []
    for host in settle_expected(expected, snapshot, now):
        drop_expect(host)
        entries.append({'at': int(now), 'key': host + ':expected', 'host': host, 'level': 'info',
                        'text': '%s is back, so it is no longer expected off.' % host, 'route': 'cleared', 'why': None})
    findings = settle(evaluate(snapshot, state, now, expected), state, now)
    results = act(choose_actions(findings, snapshot), state, mode, now)
    with open(os.path.join(CONFIG['state'], 'actions.jsonl'), 'a') as log:
        for r in results:
            log.write(json.dumps(r, ensure_ascii=False) + '\n')
    unreadable = {h for h, m in snapshot['machines'].items() if not m.get('up')}
    lines, shout, logged = notices(findings, results, state, now, local, unreadable)
    append_log(entries + logged)
    summary = morning(state, local, findings)
    if summary:
        subprocess.run([CONFIG['notify']], input=summary[:1900], text=True, capture_output=True, timeout=30)
    send(lines, shout)
    write_file(os.path.join(CONFIG['state'], 'state.json'), json.dumps(state), 0o600)
    write_file(os.path.join(CONFIG['state'], 'status.txt'), status_text(snapshot, findings, mode, now, expected))
    write_file(CONFIG['snapshot'], json.dumps({
        'version': 1, 'generated': int(now), 'mode': mode,
        'machines': [{'host': h, 'line': machine_line(h, m), 'up': m.get('up'), 'expected': h in expected} for h, m in sorted(snapshot['machines'].items())],
        'problems': [{'host': f['host'], 'level': f['level'], 'text': f['text']} for f in findings],
    }, ensure_ascii=False))
    write_file(CONFIG['textfile'], prom_lines(snapshot, findings, mode, now), 0o644)
    # The daemon reads this every 30 seconds and runs fewer turns at once while it says so; it acts on nothing else.
    why = backoff(snapshot.get('limits') or {})
    write_file(CONFIG['backoffFile'], json.dumps({'backoff': why is not None, 'reason': why, 'updatedAt': int(now)}), 0o640)
    print('butler-monitor: %d machines, %d problems, %d actions (%s), %d notices' % (
        len(snapshot['machines']), len(findings), len(results), mode, len(lines)))


def expect_command(args):
    """butler's `monitor expect`, run as butler: list, set or clear a machine's expected-off mark."""
    now = time.time()
    if not args:
        print(expected_text(read_expected(now)))
        return 0
    if args[1:] == ['clear']:
        if args[0] not in known_hosts():
            print('%s is not a machine the monitor watches' % args[0], file=sys.stderr)
            return 2
        drop_expect(args[0])
        print('%s is no longer expected off; the monitor judges it as usual from its next run.' % args[0])
        return 0
    try:
        host, until, reason = parse_expect(args, now)
    except ValueError as error:
        print(str(error), file=sys.stderr)
        return 2
    write_expect(host, until, reason, now)
    print('%s is expected off until %s (%s): the monitor will not mention it being down, asleep, locked or its keep-awake off '
          'until then, or until it is back and awake.' % (host, time.strftime('%a %H:%M', time.localtime(until)), reason))
    return 0


def main(argv):
    load_config()
    if argv[1:] == ['run']:
        run()
        return 0
    if argv[1:2] == ['expect']:
        return expect_command(argv[2:])
    print('usage: butler-monitor run | butler-monitor expect [<host> [clear | [down] [until HH:MM | for <N>h] [reason]]]', file=sys.stderr)
    return 2


if __name__ == '__main__':
    sys.exit(main(sys.argv))
