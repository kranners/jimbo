"""mac push, against a fake Mac home over a local sh; run as python3 test_push.py push.py."""
import importlib.util
import os
import subprocess
import sys
import tempfile
import time

spec = importlib.util.spec_from_file_location('push', sys.argv[1])
p = importlib.util.module_from_spec(spec)
spec.loader.exec_module(p)

base = os.path.realpath(tempfile.mkdtemp())
outbox = os.path.join(base, 'butler', 'outbox')
documents = os.path.join(base, 'butler', 'documents')
identity = os.path.join(documents, 'identity')
scratch = os.path.join(base, 'butler', 'scratch')
mac_home = os.path.join(base, 'mac-home')
state = os.path.join(base, 'state', 'pushed.json')
for folder in (outbox, identity, os.path.join(scratch, 'thread-1'), os.path.join(scratch, 'thread-2'), mac_home, os.path.join(documents, '.git')):
    os.makedirs(folder)


def write(path, body=b'data'):
    with open(path, 'wb') as handle:
        handle.write(body)
    return path


chart = write(os.path.join(outbox, 'chart.png'), b'png')
receipt = write(os.path.join(documents, 'receipt.pdf'), b'pdf')
passport = write(os.path.join(identity, 'Passport.jpg'), b'jpeg')
statement = write(os.path.join(documents, 'bank-statement.pdf'), b'statement')
token = write(os.path.join(documents, 'github-token.txt'), b'secret')
gitfile = write(os.path.join(documents, '.git', 'config'), b'x')
others = write(os.path.join(scratch, 'thread-2', 'notes.txt'), b'theirs')
mine = write(os.path.join(scratch, 'thread-1', 'notes.txt'), b'mine')
outside = write(os.path.join(base, 'elsewhere.txt'), b'no')
roots = [outbox, documents]
env = {'BUTLER_THREAD_ID': 'thread-1'}


def check(target, rest=(), extra=None):
    return p.push_check(target, list(rest), {**env, **(extra or {})}, roots, [identity], scratch, 500 << 20)


def refused(target, rest=(), extra=None):
    try:
        check(target, rest, extra)
    except p.PushRefused as error:
        return str(error)
    raise AssertionError('not refused: %s' % target)


def run(script, stdin_path):
    stdin = open(stdin_path, 'rb') if stdin_path else subprocess.DEVNULL
    try:
        done = subprocess.run(['sh', '-c', script], stdin=stdin, capture_output=True, text=True, env={'HOME': mac_home, 'PATH': os.environ.get('PATH', '/usr/bin:/bin')})
    finally:
        if stdin_path:
            stdin.close()
    return done.returncode, done.stdout, done.stderr


# An ordinary file from the outbox or documents lands in ~/butler-drop, or a named folder in ~/Downloads, and stays.
placed = p.push_run(check(chart), 'piggys-MBP', run, state)
assert placed == os.path.join(mac_home, 'butler-drop', 'chart.png'), placed
assert open(placed, 'rb').read() == b'png'
again = p.push_run(check(chart), 'piggys-MBP', run, state)
assert again != placed and again.endswith('-chart.png') and os.path.exists(placed), 'a second push keeps the first copy'
into = p.push_run(check(receipt, ['Receipts']), 'piggys-MBP', run, state)
assert into == os.path.join(mac_home, 'Downloads', 'Receipts', 'receipt.pdf'), into
assert p.push_run(check(mine), 'piggys-MBP', run, state).endswith('/butler-drop/notes.txt')

# Secrets, hidden files, another thread's scratch, anything outside the roots and odd folders are refused.
assert 'never sent' in refused(token)
assert 'hidden' in refused(gitfile)
assert 'only files butler may attach' in refused(others)
assert 'only files butler may attach' in refused(outside)
assert 'usage' in refused('relative.png')
assert 'folder is one name' in refused(chart, ['../escape'])
assert 'never sent' in refused('/etc/passwd')

# A sensitive document needs the daemon's clearance for that very file.
assert 'sensitive' in refused(passport)
assert 'sensitive' in refused(statement)
assert 'sensitive' in refused(passport, extra={'BUTLER_PUSH_SENSITIVE': '1', 'BUTLER_PUSH_FILE': statement})
cleared = {'BUTLER_PUSH_SENSITIVE': '1', 'BUTLER_PUSH_FILE': passport}
plan = check(passport, [], cleared)
assert plan['sensitive'] and not plan['keep']
assert not check(passport, ['keep'], cleared)['keep'], 'keep needs the mission item to say so, passed as BUTLER_PUSH_KEEP'
assert check(passport, ['keep'], {**cleared, 'BUTLER_PUSH_KEEP': '1'})['keep']

# A cleared sensitive copy is written, then deleted on the Mac by its own timer.
now = time.time()
copy = p.push_run(plan, 'piggys-MBP', run, state, now=now, ttl=1)
assert copy == os.path.join(mac_home, 'butler-drop', 'Passport.jpg') and open(copy, 'rb').read() == b'jpeg'
assert oct(os.stat(copy).st_mode & 0o777) == '0o600', 'written private'
for _ in range(50):
    if not os.path.exists(copy):
        break
    time.sleep(0.1)
assert not os.path.exists(copy), 'deleted after its time'
assert os.path.exists(placed), 'ordinary pushes stay'

# A Mac that slept through its timer is cleaned on the next push to it, from spike's record.
late = p.push_run(plan, 'piggys-MBP', run, state, now=now, ttl=3600)
subprocess.run(['pkill', '-f', 'sleep 3600'], capture_output=True)
assert os.path.exists(late)
p.push_run(check(receipt), 'piggys-MBP', run, state, now=now + 3601)
assert not os.path.exists(late), 'swept on the next push'
assert p.push_pending_load(state) == []

# Kept, a sensitive copy stays and is not recorded for deletion.
kept = p.push_run(check(passport, ['keep'], {**cleared, 'BUTLER_PUSH_KEEP': '1'}), 'piggys-MBP', run, state, now=now, ttl=1)
time.sleep(1.5)
assert os.path.exists(kept) and p.push_pending_load(state) == []

# The cleanup only ever deletes inside ~/butler-drop or ~/Downloads.
victim = write(os.path.join(mac_home, 'important.txt'))
run(p.push_cleanup_script([victim]), None)
assert os.path.exists(victim)
print('push: ok')
