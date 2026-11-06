"""kanban.py's thread links: a change's thread, a started session's parent and the thread cards it sends, offline."""

import io
import json
import os
import sys
import tempfile
import time
import types

root = tempfile.mkdtemp()
self_fix = os.path.join(root, 'self-fix')
for name in ('queue', 'sessions', 'progress', 'threads', 'refresh', 'watch'):
    os.makedirs(os.path.join(self_fix, name))

with open(sys.argv[1]) as f:
    source = f.read()
for placeholder, value in {
    '@host@': '{"user": "aaron", "address": "10.0.0.1"}',
    '@selfFix@': self_fix,
    '@hubMarker@': os.path.join(root, 'on-spike'),
}.items():
    source = source.replace(placeholder, value)
kanban = types.ModuleType('kanban')
exec(compile(source, 'kanban.py', 'exec'), kanban.__dict__)

failures = []


def check(name, got, want):
    if got != want:
        failures.append('%s: got %r, want %r' % (name, got, want))


# A change keeps the thread it was asked in: the launcher's record once started, the queued request's before.
with open(os.path.join(self_fix, 'queue', '20261106-100000-1.json'), 'w') as f:
    json.dump({'request': 'queued one', 'thread': '1300000000000000001'}, f)
with open(os.path.join(self_fix, 'sessions', '20261106-090000-2'), 'w') as f:
    f.write('Started https://claude.ai/code/session_abc on .claude\n')
with open(os.path.join(self_fix, 'threads', '20261106-090000-2'), 'w') as f:
    f.write('1300000000000000002\n')
with open(os.path.join(self_fix, 'sessions', '20261106-080000-3'), 'w') as f:
    f.write('Started https://claude.ai/code/session_def on .claude\n')
with open(os.path.join(self_fix, 'threads', '20261106-080000-3'), 'w') as f:
    f.write('not a thread\n')
fixes = {fix['id']: fix for fix in kanban.self_fixes()}
check('queued thread', fixes['20261106-100000-1'].get('thread'), '1300000000000000001')
check('started thread', fixes['20261106-090000-2'].get('thread'), '1300000000000000002')
check('invalid thread dropped', 'thread' in fixes['20261106-080000-3'], False)

# start_session's parent is the daemon's thread, whatever the model sent.
os.environ.update(BUTLER_THREAD_ID='1300000000000000009', BUTLER_THREAD_TITLE='Plan\nthe ' + 'x' * 200, BUTLER_DESK_SESSION='1105-3')
args = kanban.with_parent({'cwd': '/w', 'prompt': 'go', 'parent': {'thread': '99999'}})
check('parent thread', args['parent']['thread'], '1300000000000000009')
check('parent title clipped to one line', (len(args['parent']['title']) <= 100, '\n' in args['parent']['title']), (True, False))
check('parent desk', args['parent']['desk'], '1105-3')
os.environ['BUTLER_THREAD_ID'] = 'forged'
check('no parent without a real thread', 'parent' in kanban.with_parent({'parent': {'thread': '99999'}}), False)

# The thread cards file: fresh cards go whole to the board on spike, without events and approvals to pilot's.
cards_path = os.path.join(root, 'thread-cards.json')
now = time.time()
card = {'id': '1300000000000000001', 'title': 't', 'events': [{'at': 1, 'kind': 'user', 'text': 'private words'}],
        'approvals': [{'at': 1, 'headline': 'Send mail'}]}
with open(cards_path, 'w') as f:
    json.dump({'updatedAt': int(now * 1000), 'threads': [card, 'junk']}, f)
sys.stdout = io.StringIO()
on_spike = kanban.thread_cards(cards_path, now, True)
on_pilot = kanban.thread_cards(cards_path, now, False)
stale = kanban.thread_cards(cards_path, now + 11 * 60, True)
missing = kanban.thread_cards(os.path.join(root, 'none.json'), now, True)
sys.stdout = sys.__stdout__
check('on spike keeps events', on_spike['threads'][0]['events'], card['events'])
check('junk dropped', len(on_spike['threads']), 1)
check('pilot gets no events', (on_pilot['threads'][0]['events'], on_pilot['threads'][0]['approvals']), ([], []))
check('stale skipped', stale, None)
check('missing skipped', missing, None)


# A board too old for butler_threads is no failure, and the reply's two lines are printed.
def fake(reply):
    def call(tool, args, timeout=60, grace=None):
        check('tool sent', tool, 'butler_threads')
        return reply
    return call


kanban.THREAD_CARDS = cards_path
kanban.call = fake({'ok': False, 'error': 'Unknown tool butler_threads'})
sys.stdout, sys.stderr = io.StringIO(), io.StringIO()
too_old = kanban.main(['kanban', 'threads'])
kanban.call = fake({'ok': True, 'text': '1 thread cards: 1 updated, 0 removed\nCloud sessions on the board: 0'})
out = io.StringIO()
sys.stdout = out
sent = kanban.main(['kanban', 'threads'])
direct = kanban.main(['kanban', 'butler_threads'])
sys.stdout, sys.stderr = sys.__stdout__, sys.__stderr__
check('board too old', too_old, 75)
check('sent', sent, 0)
check('both lines printed', out.getvalue().count('\n') >= 2, True)
check('butler_threads refused directly', direct, 2)

if failures:
    print('\n'.join(failures))
    sys.exit(1)
print('kanban thread links: all checks passed')
