"""Runs pulse-reflex-act over a scratch spool against a fake systemctl and a fake Mac.

python3 test_act.py act.py mac-free-disk.sh
"""
import json
import os
import shutil
import stat
import sys
import tempfile
import time

ACT, MAC = sys.argv[1], sys.argv[2]
tmp = tempfile.mkdtemp()
spool, statedir = os.path.join(tmp, 'spool'), os.path.join(tmp, 'state')
for d in (spool + '/requests', spool + '/results', statedir):
    os.makedirs(d)
units_file, calls_file = os.path.join(tmp, 'units.json'), os.path.join(tmp, 'calls')

fake = os.path.join(tmp, 'systemctl')
with open(fake, 'w') as f:
    f.write('#!' + sys.executable + '''
import json, sys
units = json.load(open(%r))
open(%r, 'a').write(' '.join(sys.argv[1:]) + '\\n')
verb, unit = sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else ''
if verb == '--no-block' or (len(sys.argv) > 2 and sys.argv[2] == '--no-block'):
    unit = sys.argv[3]
u = units.get(unit)
if verb == 'show':
    u = u or {'LoadState': 'not-found'}
    for k in ('LoadState', 'ActiveState', 'SubState', 'Result', 'InactiveExitTimestampMonotonic', 'TriggeredBy'):
        print('%%s=%%s' %% (k, u.get(k, '')))
elif verb == 'reset-failed':
    u['ActiveState'], u['Result'] = 'inactive', 'success'
elif verb in ('start', 'restart'):
    u['ActiveState'], u['Result'] = ('failed', 'exit-code') if u.get('breaks') else ('active', 'success')
json.dump(units, open(%r, 'w'))
''' % (units_file, calls_file, units_file))
os.chmod(fake, 0o755)

free = {'ratio': 9}
fake_ssh = os.path.join(tmp, 'ssh')
with open(fake_ssh, 'w') as f:
    # The fake Mac runs the real script with df answering from a file and a scratch home.
    f.write('#!' + shutil.which('bash') + '''
home=%s/home; mkdir -p "$home/Library/Caches/app" "$home/Documents" "$home/.cache/kanban-runner" "$home/.cache/junk"; touch "$home/Documents/keep" "$home/Library/Caches/app/x"
bin=%s/bin; mkdir -p "$bin"
cat > "$bin/df" <<DF
#!%s
r=\\$(cat %s/ratio); echo "Filesystem 1024-blocks Used Available Capacity Mounted"; echo "disk 1000000 0 \\$((r * 10000)) 0%% /"
DF
chmod +x "$bin/df"
HOME=$home PATH=$bin:$PATH bash -s
''' % (tmp, tmp, shutil.which('bash'), tmp))
os.chmod(fake_ssh, 0o755)

gates = os.path.join(tmp, 'gates')
os.makedirs(gates)
applied = os.path.join(gates, 'applied.json')
with open(applied, 'w') as f:
    f.write('{}')
os.chmod(applied, 0o444)
if os.geteuid() == 0:
    os.chown(applied, 1000, 1000)
    os.chown(gates, 1000, 1000)
os.symlink('/etc/passwd', os.path.join(gates, 'link.json'))

config = {
    'spool': spool, 'state': statedir, 'monitorMode': os.path.join(tmp, 'mode'),
    'protect': ['butler\\.service', '.*\\.slice'],
    'units': {
        'start': ['backlogic-runner-gates\\.service', 'kanban\\.service', 'butler\\.service', 'bowerbird-worker\\.service'],
        'restart': ['kanban\\.service'],
        'timer': ['butler-feeds\\.service'],
        'run': ['butler-kanban-safe-prompts\\.service'],
    },
    'stateFiles': {applied: 'backlogic-runner-gates.service', os.path.join(gates, 'link.json'): 'kanban.service'},
    'perTargetPerHour': 3, 'perHour': 30, 'perMinute': 100, 'knownHosts': '/dev/null', 'stuckSeconds': 600, 'settleSeconds': 1,
    'macs': {'piggys-MBP': {'address': '10.0.0.2', 'user': 'aaron'}},
    'macFreeFloor': 15, 'macTimeout': 30, 'macScript': open(MAC).read(),
    'systemctl': fake, 'ssh': fake_ssh,
}
with open(os.path.join(tmp, 'config.json'), 'w') as f:
    json.dump(config, f)
uptime = int(time.monotonic() * 1_000_000)


def units(**over):
    base = {
        'backlogic-runner-gates.service': {'LoadState': 'loaded', 'ActiveState': 'failed', 'Result': 'exit-code'},
        'kanban.service': {'LoadState': 'loaded', 'ActiveState': 'activating', 'SubState': 'start', 'InactiveExitTimestampMonotonic': str(uptime - 900_000_000)},
        'butler.service': {'LoadState': 'loaded', 'ActiveState': 'failed', 'Result': 'exit-code'},
        'bowerbird-worker.service': {'LoadState': 'loaded', 'ActiveState': 'active', 'Result': 'success'},
        'butler-feeds.service': {'LoadState': 'loaded', 'ActiveState': 'failed', 'Result': 'exit-code', 'TriggeredBy': 'butler-feeds.timer'},
        'butler-kanban-safe-prompts.service': {'LoadState': 'loaded', 'ActiveState': 'inactive', 'Result': 'success'},
        'grafana.service': {'LoadState': 'loaded', 'ActiveState': 'failed', 'Result': 'exit-code'},
    }
    base.update(over)
    with open(units_file, 'w') as f:
        json.dump(base, f)


os.environ['PULSE_REFLEX_ACT_CONFIG'] = os.path.join(tmp, 'config.json')
source = open(ACT).read().replace("if __name__ == '__main__':\n    sys.exit(main(sys.argv))\n", '')
module = {'__name__': 'act'}
exec(compile(source, ACT, 'exec'), module)
module['CONFIG'].update(config)
counter = [0]


def ask(action, target, raw=None):
    counter[0] += 1
    rid = 'r%d' % counter[0]
    with open(os.path.join(spool, 'requests', rid + '.json'), 'w') as f:
        f.write(raw if raw is not None else json.dumps({'action': action, 'target': target}))
    module['run']()
    assert not os.listdir(os.path.join(spool, 'requests')), 'requests are always consumed'
    with open(os.path.join(spool, 'results', rid + '.json')) as f:
        return json.load(f)


def expect(result, outcome, words=''):
    assert result['result'] == outcome and words in json.dumps(result), result
    print('ok', outcome, result.get('action'), result.get('target'), result.get('reason') or result.get('after'))


units()
expect(ask('start-failed', 'backlogic-runner-gates.service'), 'done', 'active')
expect(ask('start-failed', 'backlogic-runner-gates.service'), 'refused', 'not failed')
expect(ask('start-failed', 'butler.service'), 'refused', 'protected')
expect(ask('start-failed', 'grafana.service'), 'refused', 'not on the start allowlist')
expect(ask('start-failed', 'kanban-bridge.service'), 'refused', 'not on the start allowlist')
expect(ask('rm -rf', '/'), 'refused', 'not an action')
expect(ask(None, None, raw='not json'), 'refused', 'malformed')
expect(ask('start-unit', 'butler-kanban-safe-prompts.service'), 'done')
expect(ask('start-unit', 'bowerbird-worker.service'), 'refused', 'not on the run allowlist')
expect(ask('retry-timer', 'butler-feeds.service'), 'done', 'active')
expect(ask('retry-timer', 'butler-feeds.service'), 'refused', 'did not fail')

# Stuck activating: 15 minutes is stuck, 1 minute is not.
expect(ask('restart-stuck', 'kanban.service'), 'done', 'active')
units(**{'kanban.service': {'LoadState': 'loaded', 'ActiveState': 'activating', 'SubState': 'start', 'InactiveExitTimestampMonotonic': str(uptime - 60_000_000)}})
expect(ask('restart-stuck', 'kanban.service'), 'refused', 'under 600s')
# A unit waiting out RestartSec keeps its old timestamp, but is not stuck.
units(**{'kanban.service': {'LoadState': 'loaded', 'ActiveState': 'activating', 'SubState': 'auto-restart', 'InactiveExitTimestampMonotonic': str(uptime - 9_000_000_000)}})
expect(ask('restart-stuck', 'kanban.service'), 'refused', 'not stuck starting')

# A unit that breaks again is reported as failed after, for pulse's verify step.
units(**{'backlogic-runner-gates.service': {'LoadState': 'loaded', 'ActiveState': 'failed', 'Result': 'exit-code', 'breaks': True}})
expect(ask('start-failed', 'backlogic-runner-gates.service'), 'done', 'failed')

# The channel's own ceiling: three in an hour per target, whatever pulse asks.
expect(ask('start-failed', 'backlogic-runner-gates.service'), 'done')
expect(ask('start-failed', 'backlogic-runner-gates.service'), 'refused', 'acted on 3 times')
# The ceiling is per target, whichever action asks.
expect(ask('retry-timer', 'backlogic-runner-gates.service'), 'refused', 'acted on 3 times')

# Both kill switches.
units()
open(os.path.join(spool, 'off'), 'w').close()
expect(ask('start-unit', 'butler-kanban-safe-prompts.service'), 'refused', 'reflexes are off')
os.unlink(os.path.join(spool, 'off'))
with open(config['monitorMode'], 'w') as f:
    f.write('off\n')
expect(ask('start-unit', 'butler-kanban-safe-prompts.service'), 'refused', 'monitor act off')
os.unlink(config['monitorMode'])
os.mkfifo(config['monitorMode'])
expect(ask('start-unit', 'butler-kanban-safe-prompts.service'), 'done')  # a FIFO never blocks root
os.unlink(config['monitorMode'])
with open(config['monitorMode'], 'w') as f:
    f.write('dry-run\n')

# The read-only stamp gets its owner's write bit back, never deleted; a symlink and an unlisted path are refused.
units(**{'backlogic-runner-gates.service': {'LoadState': 'loaded', 'ActiveState': 'failed', 'Result': 'exit-code'}})
module['load_state']  # state carries on
os.unlink(os.path.join(statedir, 'state.json'))
expect(ask('unblock-state-file', applied), 'done', '0o644')
assert os.stat(applied).st_mode & stat.S_IWUSR and open(applied).read() == '{}'
expect(ask('unblock-state-file', applied), 'refused', 'already writable')
expect(ask('unblock-state-file', os.path.join(gates, 'link.json')), 'refused', 'cannot be opened safely')
expect(ask('unblock-state-file', '/etc/shadow'), 'refused', 'not a state file')
other = os.path.join(tmp, 'other.json')
with open(other, 'w') as f:
    f.write('x')
os.chmod(applied, 0o444)
os.unlink(applied)
os.link(other, applied)
os.chmod(applied, 0o444)
if os.geteuid() == 0:
    os.chown(applied, 1000, 1000)
expect(ask('unblock-state-file', applied), 'refused', 'hard link')

# The Mac: over its floor nothing is touched; under it, caches go and documents stay.
with open(os.path.join(tmp, 'ratio'), 'w') as f:
    f.write('40')
expect(ask('mac-free-disk', 'piggys-MBP'), 'refused', 'over its floor')
assert os.path.exists(os.path.join(tmp, 'home/Library/Caches/app/x'))
with open(os.path.join(tmp, 'ratio'), 'w') as f:
    f.write('9')
expect(ask('mac-free-disk', 'piggys-MBP'), 'done', 'before')
assert not os.listdir(os.path.join(tmp, 'home/Library/Caches')), 'caches cleared'
assert os.path.exists(os.path.join(tmp, 'home/Documents/keep')), 'documents kept'
assert os.listdir(os.path.join(tmp, 'home/.cache')) == ['kanban-runner'], 'the runner cache kept'
expect(ask('mac-free-disk', 'pilot'), 'refused', 'not a machine')

# Stray files, dotfiles and folders in requests/ are removed unread, so the path unit never loops.
with open(os.path.join(spool, 'requests', 'Bad Name.json'), 'w') as f:
    f.write('{}')
open(os.path.join(spool, 'requests', '.half.tmp'), 'w').close()
os.makedirs(os.path.join(spool, 'requests', 'sub', 'deeper'))
os.symlink('/etc', os.path.join(spool, 'requests', 'link'))
module['run']()
assert not os.listdir(os.path.join(spool, 'requests')) and os.path.isdir('/etc')

# A flood past the per-minute cap is dropped unanswered.
module['CONFIG']['perMinute'] = 2
os.unlink(os.path.join(statedir, 'state.json'))
for n in range(5):
    with open(os.path.join(spool, 'requests', 'f%d.json' % n), 'w') as f:
        f.write('{"action": "nope", "target": "x"}')
module['run']()
answered = [n for n in os.listdir(os.path.join(spool, 'results')) if n.startswith('f')]
assert len(answered) == 2 and not os.listdir(os.path.join(spool, 'requests')), answered
print('pulse-reflex-act: ok')
