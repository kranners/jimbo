"""butler-monitor: watches Aaron's machines and resources, tells him through butler, and in act mode takes only safe steps.

One run every couple of minutes, as root on spike: collect, judge against the thresholds, choose actions, act or log what
it would do, notify, and write the status butler reads, the Machines snapshot and node_exporter's textfile.
The judging, action choice and notice wording are pure functions of a snapshot and the saved state, so the tests drive
them with fake machines.
"""

import base64
import concurrent.futures
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


def collect_spike_extras():
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
    try:
        extras['system_generations'] = len([n for n in os.listdir('/nix/var/nix/profiles') if re.fullmatch(r'system-[0-9]+-link', n)])
    except OSError:
        pass
    return extras


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


def collect():
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
        machines['spike'].update(collect_spike_extras())
    return {'machines': machines, 'claude': read_limits(), 'work': read_work()}


# ---------------------------------------------------------------- judging

def gb(value):
    return '%.0f GB' % (value / GB) if value >= 10 * GB else '%.1f GB' % (value / GB)


def finding(key, host, level, text, urgent=False, repeat=None, hold=0):
    return {'key': key, 'host': host, 'level': level, 'text': text, 'urgent': urgent, 'repeat': repeat, 'hold': hold}


def evaluate(snapshot, state, now):
    """Every problem in this snapshot, before holds and repeats are applied."""
    out = []
    down = state.setdefault('down_since', {})
    for host, m in sorted(snapshot['machines'].items()):
        if m.get('up') is None:
            out.append(finding('%s:unknown' % host, host, 'warn', "Couldn't read %s: %s." % (host, m.get('why', 'no answer')), repeat=6 * 3600))
            continue
        if not m.get('up'):
            since = down.setdefault(host, now)
            minutes = (now - since) / 60
            if minutes >= th('downMinutes'):
                always = host in CONFIG['alwaysOn']
                out.append(finding('%s:down' % host, host, 'act' if always else 'warn',
                                   '%s has been unreachable for %s (%s).' % (host, duration(now - since), m.get('why', 'no answer')),
                                   urgent=always, repeat=3600 if always else None))
            continue
        down.pop(host, None)
        out += judge_machine(host, m)
    for account, percent in sorted((snapshot.get('claude') or {}).items()):
        if percent >= th('claudeActPercent'):
            out.append(finding('claude:%s' % account, 'claude', 'act',
                               "The %s Claude account is at %.0f%% of its week; butler and the runner move to the next account on their own." % (account, percent),
                               urgent=False, repeat=12 * 3600))
        elif percent >= th('claudeWarnPercent'):
            out.append(finding('claude:%s' % account, 'claude', 'warn',
                               'The %s Claude account is at %.0f%% of its week.' % (account, percent), repeat=24 * 3600))
    work = snapshot.get('work')
    if work:
        if work['running'] > th('maxRunningChanges'):
            out.append(finding('work:running', 'spike', 'warn', '%d changes are running at once.' % work['running'], repeat=6 * 3600))
        for change in work['long']:
            if now - change['started'] > th('maxChangeHours') * 3600:
                out.append(finding('work:long:%s' % change['id'], 'spike', 'warn',
                                   'The change "%s" has been running for %s.' % (change['title'], duration(now - change['started'])), repeat=6 * 3600))
    return out


def judge_machine(host, m):
    out = []
    free, total = m.get('disk_free_bytes'), m.get('disk_total_bytes')
    if free is not None and total:
        ratio = free / total
        text = "%s's disk has %s free (%.0f%%)." % (host, gb(free), ratio * 100)
        if ratio < th('diskActRatio') or free < th('diskActGB') * GB:
            out.append(finding('%s:disk' % host, host, 'act', text, urgent=True, repeat=4 * 3600))
        elif ratio < th('diskWarnRatio') or free < th('diskWarnGB') * GB:
            out.append(finding('%s:disk' % host, host, 'warn', text, repeat=12 * 3600))
    mem = m.get('mem_free_ratio')
    if mem is not None:
        text = '%s has %.0f%% of its memory free.' % (host, mem * 100)
        if mem < th('memActRatio'):
            out.append(finding('%s:memory' % host, host, 'act', text, urgent=True, repeat=4 * 3600, hold=th('memActMinutes') * 60))
        if mem < th('memWarnRatio'):
            out.append(finding('%s:memory' % host, host, 'warn', text, repeat=12 * 3600))
    if m.get('pressure') == 'critical':
        out.append(finding('%s:pressure' % host, host, 'act', '%s is under critical memory pressure.' % host, urgent=True, repeat=4 * 3600))
    if (m.get('load_ratio') or 0) > th('loadRatio'):
        out.append(finding('%s:load' % host, host, 'warn', "%s's load has averaged %.1f over 15 minutes on %d cores." % (
            host, m['load15'], m['cores']), repeat=6 * 3600))
    awake = m.get('keepawake')
    if m.get('on_battery') and awake == 'on' and m.get('battery') is not None:
        text = '%s is on battery at %.0f%% with keep-awake on.' % (host, m['battery'])
        if m['battery'] < th('batteryActPercent'):
            out.append(finding('%s:battery' % host, host, 'act', text, urgent=True, repeat=3600))
        elif m['battery'] < th('batteryWarnPercent'):
            out.append(finding('%s:battery' % host, host, 'warn', text, repeat=6 * 3600))
    if awake == 'on' and m.get('locked') == 'yes' and m.get('os') == 'macos':
        out.append(finding('%s:locked' % host, host, 'warn', "%s's screen is locked though keep-awake is on." % host, repeat=12 * 3600))
    if awake == 'off' and host in CONFIG['keepAwakeHosts']:
        out.append(finding('%s:keepawake' % host, host, 'act', "%s's keep-awake is off." % host, repeat=12 * 3600))
    for unit in m.get('failed_units') or []:
        out.append(finding('%s:failed:%s' % (host, unit), host, 'warn', '%s has failed on %s.' % (unit, host), repeat=12 * 3600))
    if m.get('docker_build_cache_bytes', 0) > th('dockerCacheGB') * GB:
        out.append(finding('spike:docker', host, 'warn', "Docker's build cache on spike holds %s." % gb(m['docker_build_cache_bytes']), repeat=24 * 3600))
    if m.get('system_generations', 0) > th('maxGenerations'):
        out.append(finding('spike:generations', host, 'warn', 'spike keeps %d system generations.' % m['system_generations'], repeat=24 * 3600))
    return out


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
        if f['key'].endswith(':keepawake') and f['host'] in CONFIG['keepAwakeHosts'] and f['host'] not in CONFIG['readOnlyHosts']:
            actions.append(('keepawake-on', f['host']))
    for unit in spike.get('failed_units') or []:
        if re.fullmatch(CONFIG['restartable'], unit) and unit not in CONFIG['neverRestart']:
            actions.append(('restart:' + unit, 'spike'))
    tight = any(f['level'] == 'act' and (f['key'].startswith('claude:') or f['host'] == 'spike') for f in findings)
    actions.append(('hold-work' if tight else 'release-work', 'spike'))
    return actions


def describe(name, host):
    if name.startswith('restart:'):
        return 'restart %s on spike once' % name.split(':', 1)[1]
    return {
        'clean-outbox': "delete butler's own outbox pictures older than 2 days and spike's aged temp files",
        'journal-vacuum': "shrink spike's journal to %s" % CONFIG['journalVacuum'],
        'docker-prune': "clear Docker's build cache and dangling images on spike",
        'gc-generations': 'collect Nix garbage on spike, keeping the newest %d system generations' % CONFIG['keepGenerations'],
        'keepawake-on': "turn %s's keep-awake back on" % host,
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
    if name == 'keepawake-on':
        target = resolve(host)
        if target is None:
            raise RuntimeError('%s did not answer' % host)
        result = remote(target, KEEPAWAKE_ON[target['os']], timeout=40)
        if 'ok' not in result.stdout:
            raise RuntimeError((result.stderr.strip() or 'no ok')[:160])
        return 'off', 'on'
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
        elif ident in last and now - last[ident] < 3600:
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


def notices(findings, results, state, now, local, unreadable=()):
    """What to tell Aaron now: (dm lines, shout line or None); the rest waits in state for the morning summary."""
    sent = state.setdefault('sent', {})
    lines, urgent = [], []
    current = {f['key']: f for f in findings}
    for f in findings:
        previous = sent.get(f['key'])
        due = previous is None or rank(f['level']) > rank(previous['level']) or (
            f['repeat'] is not None and now - previous['at'] >= f['repeat'])
        if not due:
            continue
        sent[f['key']] = {'at': now, 'level': f['level'], 'text': f['text'], 'missing': 0}
        lines.append(f)
    cleared = []
    for key, entry in list(sent.items()):
        if key in current:
            entry['missing'] = 0
            continue
        # A machine that is down says nothing about its disk or memory, and a problem must be gone for three runs.
        if key.split(':', 1)[0] in unreadable and not key.endswith((':down', ':unknown')):
            continue
        entry['missing'] = entry.get('missing', 0) + 1
        if entry['missing'] >= 3:
            cleared.append(sent.pop(key)['text'])
    quiet = in_quiet(local)
    out, overnight = [], state.setdefault('overnight', [])
    for f in lines:
        text = ('⚠️ ' if f['level'] == 'act' else '') + f['text']
        if quiet and not f['urgent']:
            overnight.append(text)
        else:
            out.append(text)
            if f['urgent']:
                urgent.append(f['text'])
    for r in results:
        if quiet and r['result'] == 'dry-run':
            overnight.append(r['line'])
        else:
            out.append(r['line'])
            if r['result'] != 'dry-run':
                urgent.append(r['line'])
    for text in cleared:
        (overnight if quiet else out).append('Resolved: ' + text)
    shout = None
    if urgent:
        shout = 'Monitor: ' + urgent[0]
        if len(urgent) > 1:
            shout += ' And %d more in Discord.' % (len(urgent) - 1)
        shout = shout[:200]
    return out, shout


def morning(state, local, findings):
    today = time.strftime('%Y-%m-%d', local)
    hm = '%02d:%02d' % (local.tm_hour, local.tm_min)
    if hm < CONFIG['quiet']['summary'] or in_quiet(local) or state.get('summary_date') == today:
        return None
    state['summary_date'] = today
    overnight = state.pop('overnight', [])
    if not overnight:
        return None
    open_items = [f['text'] for f in findings]
    text = ['Good morning. Overnight the monitor noted:'] + ['- ' + x for x in overnight[-15:]]
    if open_items:
        text += ['Still open now:'] + ['- ' + x for x in open_items[:10]]
    return '\n'.join(text)


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


def status_text(snapshot, findings, mode, now):
    lines = ['Monitor checked at %s; acting is %s.' % (time.strftime('%H:%M', time.localtime(now)), mode)]
    lines += [machine_line(h, m) for h, m in sorted(snapshot['machines'].items())]
    for account, percent in sorted((snapshot.get('claude') or {}).items()):
        lines.append('Claude %s: %.0f%% of the week' % (account, percent))
    lines.append('Open problems: ' + ('; '.join(f['text'] for f in findings) if findings else 'none'))
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
    for level in ('warn', 'act'):
        out.append('butler_monitor_findings{level="%s"} %d' % (level, sum(f['level'] == level for f in findings)))
    return '\n'.join(out) + '\n'


def send(lines, shout):
    if lines:
        text = 'Machines monitor:\n' + '\n'.join('- ' + x for x in lines)
        subprocess.run([CONFIG['notify']], input=text[:1900], text=True, capture_output=True, timeout=30)
    if shout:
        subprocess.run([CONFIG['callSay'], '--urgent', '--call-only'], input=shout, text=True, capture_output=True, timeout=30)


def load_state():
    try:
        with open(os.path.join(CONFIG['state'], 'state.json')) as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def run():
    now = time.time()
    local = time.localtime(now)
    state = load_state()
    mode = read_mode()
    snapshot = collect()
    findings = settle(evaluate(snapshot, state, now), state, now)
    results = act(choose_actions(findings, snapshot), state, mode, now)
    with open(os.path.join(CONFIG['state'], 'actions.jsonl'), 'a') as log:
        for r in results:
            log.write(json.dumps(r, ensure_ascii=False) + '\n')
    unreadable = {h for h, m in snapshot['machines'].items() if not m.get('up')}
    lines, shout = notices(findings, results, state, now, local, unreadable)
    summary = morning(state, local, findings)
    if summary:
        subprocess.run([CONFIG['notify']], input=summary[:1900], text=True, capture_output=True, timeout=30)
    send(lines, shout)
    write_file(os.path.join(CONFIG['state'], 'state.json'), json.dumps(state), 0o600)
    write_file(os.path.join(CONFIG['state'], 'status.txt'), status_text(snapshot, findings, mode, now))
    write_file(CONFIG['snapshot'], json.dumps({
        'version': 1, 'generated': int(now), 'mode': mode,
        'machines': [{'host': h, 'line': machine_line(h, m), 'up': m.get('up')} for h, m in sorted(snapshot['machines'].items())],
        'problems': [{'host': f['host'], 'level': f['level'], 'text': f['text']} for f in findings],
    }, ensure_ascii=False))
    write_file(CONFIG['textfile'], prom_lines(snapshot, findings, mode, now), 0o644)
    print('butler-monitor: %d machines, %d problems, %d actions (%s), %d notices' % (
        len(snapshot['machines']), len(findings), len(results), mode, len(lines)))


def main(argv):
    load_config()
    if argv[1:] == ['run']:
        run()
        return 0
    print('usage: butler-monitor run', file=sys.stderr)
    return 2


if __name__ == '__main__':
    sys.exit(main(sys.argv))
