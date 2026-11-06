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

# Root reads the file from butler's home, so a link planted there is refused, and so is a file past the cap.
link = os.path.join(root, 'linked.json')
os.symlink(cards_path, link)
big = os.path.join(root, 'big.json')
with open(big, 'w') as f:
    f.write(' ' * (kanban.THREAD_CARDS_BYTES + 1))
many = os.path.join(root, 'many.json')
with open(many, 'w') as f:
    json.dump({'updatedAt': int(now * 1000), 'threads': [dict(card, id=str(10000 + n)) for n in range(100)]}, f)
sys.stdout, sys.stderr = io.StringIO(), io.StringIO()
linked = kanban.thread_cards(link, now, True)
too_big = kanban.thread_cards(big, now, True)
capped = kanban.thread_cards(many, now, True)
sys.stdout, sys.stderr = sys.__stdout__, sys.__stderr__
check('symlink refused', linked, None)
check('oversized refused', too_big, None)
check('capped at 80', len(capped['threads']), 80)


# A board too old for butler_threads is no failure, and the reply's two lines are printed.
sent_tools = []


def fake(reply):
    def call(tool, args, timeout=60, grace=None):
        sent_tools.append(tool)
        if tool == 'tidy':
            return {'ok': True, 'text': 'Tidied the board: 0 cards archived'}
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
check('a sync that reached the board tidies it after', sent_tools, ['butler_threads', 'butler_threads', 'tidy'])

# A board older than session parents refuses the argument, so the session is started again without it.
calls = []


def old_board(tool, args, timeout=60, grace=None):
    calls.append(dict(args))
    if 'parent' in args:
        return {'ok': False, 'error': 'Unknown argument parent'}
    return {'ok': True, 'text': 'Started session s1'}


os.environ['BUTLER_THREAD_ID'] = '1300000000000000009'
kanban.call = old_board
kanban.with_context = lambda tool, args: (args, None)
sys.stdin = io.StringIO(json.dumps({'cwd': '/w', 'prompt': 'go'}))
sys.stdout = io.StringIO()
started = kanban.main(['kanban', 'start_session'])
sys.stdout, sys.stdin = sys.__stdout__, sys.__stdin__
check('old board still starts the session', (started, len(calls), 'parent' in calls[0], 'parent' in calls[-1]), (0, 2, True, False))

# A change's times and outcome, for the board's archive: started from its session record, finished once it ended.
os.makedirs(os.path.join(self_fix, 'progress'), exist_ok=True)
with open(os.path.join(self_fix, 'sessions', '20261106-120000-7'), 'w') as f:
    f.write('Started https://claude.ai/code/session_t\n')
with open(os.path.join(self_fix, 'progress', '20261106-120000-7'), 'w') as f:
    f.write('State: finished\n')
os.utime(os.path.join(self_fix, 'sessions', '20261106-120000-7'), (1000, 1000))
os.utime(os.path.join(self_fix, 'progress', '20261106-120000-7'), (2000, 2000))
check('finished change times', kanban.times_of('20261106-120000-7', 'finished'), {'startedAt': 1000000, 'finishedAt': 2000000, 'outcome': 'done'})
check('failed change outcome', kanban.times_of('20261106-120000-7', 'finished with an error').get('outcome'), 'failed')
check('running change has no finish', kanban.times_of('20261106-120000-7', 'running'), {'startedAt': 1000000})

# Board questions: a waiting AskUserQuestion is read once, spooled for the daemon, and Aaron's answer goes back with the session's own labels.
shown = """fix the tests asks:
1. [Approach] Which way should I go? (one of, or a free-text answer)
   - "Narrow": Smallest change
   - "Broad and a very long label that the daemon's buttons cut short somewhere past eighty characters wide"
2. Which files? (any of, or a free-text answer)
   - "a.ts"
   - "b.ts": the other one
Prompt id: 0123abcd4567"""
parsed = kanban.parse_question(shown)
check('question prompt id', parsed['prompt'], '0123abcd4567')
check('question shape', [(q['header'], q['multiSelect'], [o['label'] for o in q['options']]) for q in parsed['questions']],
      [('Approach', False, ['Narrow', "Broad and a very long label that the daemon's buttons cut short somewhere past eighty characters wide"]), ('', True, ['a.ts', 'b.ts'])])
check('a permission prompt is no question', kanban.parse_question('s asks permission for Bash:\nrun it?\n- "Yes"\nPrompt id: abc'), None)

board = os.path.join(root, 'board')
os.makedirs(board)
kanban.BOARD = board
calls = []
replies = {
    'board_snapshot': {'ok': True, 'text': 'Board: 2 sessions\n' + json.dumps({'sessions': [
        {'id': 'sess-1', 'name': 'fix the tests', 'activity': 'needs-you', 'needs': 'a question'},
        {'id': 'sess-2', 'name': 'other', 'activity': 'working'},
    ]})},
}
def fake_call(tool, args, timeout=60, grace=None):
    calls.append((tool, args))
    if tool == 'answer_prompt' and 'prompt' not in args:
        return {'ok': True, 'text': shown}
    if tool == 'note':
        return {'ok': True, 'text': 'Noted (id butler-note-1)'}
    return replies.get(tool, {'ok': True, 'text': ''})
kanban.call = fake_call
state = {'asked': {}, 'answered': set(), 'read': {}, 'notes': {}, 'at': 0}
kanban.questions_once(None, state)
kanban.questions_once(None, state)
pending = os.listdir(os.path.join(board, 'questions', 'pending'))
check('one question spooled once', pending, ['b-sess-1-0123abcd4567.json'])
check('read once per waiting state', len([c for c in calls if c[0] == 'answer_prompt']), 1)
with open(os.path.join(board, 'questions', 'pending', pending[0])) as f:
    spooled = json.load(f)
check('spooled labels clipped', len(spooled['questions'][0]['options'][1]['label']) <= 80, True)
with open(os.path.join(board, 'questions', 'open.json')) as f:
    check('open list', json.load(f), {'ids': ['b-sess-1-0123abcd4567']})
with open(os.path.join(board, 'questions', 'posted', 'b-sess-1-0123abcd4567.json'), 'w') as f:
    json.dump({'id': 'b-sess-1-0123abcd4567', 'session': 'sess-1', 'link': 'https://discord.com/channels/@me/123/456'}, f)
with open(os.path.join(board, 'questions', 'answers', 'b-sess-1-0123abcd4567.json'), 'w') as f:
    json.dump({'id': 'b-sess-1-0123abcd4567', 'answers': [{'selected': [spooled['questions'][0]['options'][1]['label']], 'other': None}, {'selected': [], 'other': 'both'}]}, f)
calls.clear()
kanban.questions_once(None, state)
answered = [c[1] for c in calls if c[0] == 'answer_prompt' and 'prompt' in c[1]]
check('answer sent with the original label', answered, [{'session': 'sess-1', 'prompt': '0123abcd4567', 'answers': [
    {'selected': ["Broad and a very long label that the daemon's buttons cut short somewhere past eighty characters wide"]}, {'selected': [], 'other': 'both'}]}])
check('answered question not asked again', os.listdir(os.path.join(board, 'questions', 'pending')), ['b-sess-1-0123abcd4567.json'])
os.remove(os.path.join(board, 'questions', 'pending', 'b-sess-1-0123abcd4567.json'))
kanban.questions_once(None, state)
check('not spooled again while still showing', os.listdir(os.path.join(board, 'questions', 'pending')), [])
with open(os.path.join(board, 'questions', 'answers', 'x.json'), 'w') as f:
    json.dump({'id': 'b-forged', 'answers': [{'selected': ['Yes']}]}, f)
calls.clear()
kanban.questions_once(None, state)
check('an answer to a question never asked is dropped', [c for c in calls if c[0] == 'answer_prompt' and 'prompt' in c[1]], [])

if failures:
    print('\n'.join(failures))
    sys.exit(1)
print('kanban thread links: all checks passed')
