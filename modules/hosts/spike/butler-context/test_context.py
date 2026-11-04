"""Builds every context pack from fixture memory, a fake board and a fake pilot, offline.

It fails if anything private, a secret, a message body or a Bloom file's
contents reaches a pack, if a pack outgrows its limit, or if the areas,
prefixes and the command's verbs stop working.
"""
import json
import os
import subprocess
import sys
import tempfile

SOURCE = sys.argv[1]
root = tempfile.mkdtemp()
packs = os.path.join(root, 'packs')
refresh = os.path.join(root, 'refresh')
memory = os.path.join(root, 'memory')
for d in (packs, refresh, memory + '/core', memory + '/journal', memory + '/skills/skynet', memory + '/skills/garmin', memory + '/skills/machines'):
    os.makedirs(d)


def write(path, text, mode=None):
    with open(path, 'w') as f:
        f.write(text)
    if mode:
        os.chmod(path, mode)


write(memory + '/core/now.md', '''# Now
## Doing
- Kanban board: keep one card per change and tidy regions on the board.
- Bloom HKJC odds recorder backfill is waiting on Mat's capture PR re-cut.
- Check Ticketek for a gig ticket; a $90.70 charge on 28 Oct may be it.
- Accounts: sign in to Westpac and Citibank to download exports.
- Tokyo trip 16-22 Dec is in the calendar, licence and IDP by 4 Dec.
- Framer panel should show the dim Butler on the dark screen.
- Garmin sleep score was low all week.
- Email Jo about the bond loan.
- Zones: create Parkhouse at -37.8110020, 145.0092509.
- Butler's landing queue holds deploys during calls.
''')
write(memory + '/core/training.md', '- Bloom training plan: squat 100 kg on Mondays.\n')
write(memory + '/core/operating.md', '- Butler call Aaron on 0412 345 678 if the board is down.\n- The token for the board is ghp_abcdefghijklmnopqrstuvwxyz123456.\n')
write(memory + '/journal/2026-11-03.md', '''
## 09:00
Morning report for Bloom: HKJC history backfill is laptop-only on pilot. Second sentence with detail.

## 10:00
Read Aaron's mail from the Bloom HR team about his salary.

## 11:00
Moved the board's HKJC region to the left.
''')
write(memory + '/skills/skynet/SKILL.md', '---\nname: skynet\ndescription: Read Bloom\'s skynet knowledge base live from pilot. More.\n---\n')
write(memory + '/skills/garmin/SKILL.md', '---\nname: garmin\ndescription: Read Garmin sleep and HRV for training.\n---\n')
write(memory + '/skills/machines/SKILL.md', '---\nname: machines\ndescription: What is on Aaron\'s machines, framer and spike included.\n---\n')
digest = os.path.join(root, 'builders.md')
write(digest, '''Refreshed: now
## Open changes

### 20261104-105956-993339: Butler context packs
- State: running; waits on Aaron: no
- Brief: shared context for the kanban board and framer.

### 20261104-110000-1: HKJC capture alert
- State: queued; waits on Aaron: no
- Brief: Bloom HKJC capture alert.

## Landed or closed in the last 48 hours

### 20261104-095352-526805: Kanban board approval grants
- State: archived; waits on Aaron: no
''')
board = {
    'sessions': [
        {'id': 'aaaa-1111', 'short': 'a1', 'name': 'racemate machine encoding', 'state': 'working', 'cwd': '/Users/aaronpierce/workspace/omnidash--racemate', 'summary': 'Encoding machine ids for racemate.'},
        {'id': 'bbbb-2222', 'short': 'b2', 'name': 'hkjc production deployment', 'state': 'needs-you', 'cwd': '/Users/aaronpierce/bloom-data-hkjc', 'summary': 'Waiting on approval to deploy.'},
        {'id': 'cccc-3333', 'short': 'c3', 'name': 'kanban runners', 'state': 'idle', 'cwd': '/Users/aaronpierce/workspace/kanban', 'summary': 'Runners landed.'},
        {'id': 'dddd-4444', 'short': 'd4', 'name': 'old', 'state': 'done', 'cwd': '/Users/aaronpierce/bloom-data-tennis', 'summary': 'Finished.'},
    ],
    'regions': [{'name': 'HKJC'}, {'name': 'Butler'}],
}
kanban = os.path.join(root, 'kanban')
write(kanban, '#!/bin/sh\ncat >/dev/null\necho \'%s\'\n' % json.dumps(board), 0o755)
ssh = os.path.join(root, 'ssh')
write(ssh, '''#!/bin/sh
cat >/dev/null
printf 'repo\\t~/bloom-data-hkjc\\tmain\\t2 hours ago\\t3\\n'
printf 'commit\\t~/bloom-data-hkjc\\tRepair scores history publish\\n'
printf 'pr\\t~/bloom-data-hkjc\\t#9 Capture re-cut (mat/capture)\\n'
printf 'readme\\t~/bloom-data-hkjc\\tREADME.md\\tHKJC data\\n'
printf 'skynet\\tcore/lookup.md\\n'
''', 0o755)
env = dict(os.environ,
           BUTLER_CONTEXT_DIR=packs, BUTLER_CONTEXT_REFRESH=refresh, BUTLER_CONTEXT_MEMORY=memory,
           BUTLER_CONTEXT_DIGEST=digest, BUTLER_CONTEXT_KANBAN=kanban, BUTLER_CONTEXT_SSH=ssh,
           BUTLER_CONTEXT_PILOT='{"user": "aaronpierce", "address": "10.100.0.11"}', BUTLER_CONTEXT_GROUP='')
failures = []


def run(*args, stdin=''):
    return subprocess.run([sys.executable, SOURCE, *args], input=stdin, capture_output=True, text=True, env=env)


def check(condition, message):
    if not condition:
        failures.append(message)


result = run('generate')
check(result.returncode == 0, 'generate failed: %s' % result.stderr)
texts = {}
for area in ('board', 'bloom', 'home', 'butler', 'personal'):
    path = os.path.join(packs, area + '.md')
    check(os.path.exists(path), 'no %s pack' % area)
    texts[area] = open(path).read() if os.path.exists(path) else ''
    check(len(texts[area]) <= 6100, '%s pack is %d characters' % (area, len(texts[area])))
everything = '\n'.join(texts.values())
for private in ('90.70', 'Westpac', 'Garmin sleep', 'bond loan', '-37.8110020', '0412 345 678', 'ghp_', 'salary', 'squat', 'Second sentence'):
    check(private not in everything, 'private or secret text reached a pack: %s' % private)
check('racemate machine encoding' in texts['bloom'], 'bloom pack misses a Bloom session')
check('kanban runners' not in texts['bloom'], 'bloom pack lists a session from another area')
check('kanban runners' in texts['board'] and 'racemate' in texts['board'], 'board pack misses sessions')
check('old [done]' not in texts['board'], 'board pack lists a finished session')
check('~/bloom-data-hkjc: on main' in texts['bloom'] and '#9 Capture re-cut' in texts['bloom'], 'bloom pack misses pilot facts')
check('core/lookup.md' in texts['bloom'], 'bloom pack misses the skynet index')
check('`skynet`' in texts['bloom'], 'bloom pack misses its skill')
check('`garmin`' not in everything, 'a health skill reached a pack')
check('Tokyo trip' in texts['personal'], 'personal pack misses a plan')
check('Framer panel' in texts['home'], 'home pack misses the panel')
check('20261104-105956-993339 Butler context packs' in texts['butler'], 'butler pack misses a change in flight')
check('HKJC capture alert' in texts['bloom'], 'bloom pack misses its change in flight')
check('HKJC capture alert' not in texts['personal'], 'personal pack lists an unrelated change')
check('Morning report for Bloom' in texts['bloom'], 'bloom pack misses the journal')

index = run('list').stdout
check('`bloom`' in index and 'context show' in index, 'list does not print the index')
check(run('show', 'bloom').stdout == texts['bloom'], 'show does not print the pack')
check(run('show', 'nope').returncode == 2, 'show takes an unknown area')

prefix = run('prefix', stdin=json.dumps({'cwd': '/Users/aaronpierce/bloom-data-hkjc', 'text': 'back up history'})).stdout
check(prefix.startswith("Context from Butler: spike's bloom pack") and prefix.rstrip().endswith('--- end of context ---'), 'prefix by folder is wrong:\n' + prefix[:200])
check(len(prefix) < 3900, 'prefix is too long')
prefix = run('prefix', stdin=json.dumps({'cwd': '/tmp/elsewhere', 'text': 'fix the framer panel and home assistant'})).stdout
check("spike's home pack" in prefix, 'prefix by text is wrong')
prefix = run('prefix', stdin=json.dumps({'cwd': '', 'text': 'nothing to match', 'default': 'butler'})).stdout
check("spike's butler pack" in prefix, 'prefix default is wrong')
check(run('prefix', stdin=json.dumps({'text': 'nothing to match'})).stdout == '', 'prefix with no area printed something')

# Pilot and the board unreachable: the last good answer stays, marked with when it was read.
write(kanban, '#!/bin/sh\necho unreachable >&2\nexit 75\n', 0o755)
write(ssh, '#!/bin/sh\nexit 255\n', 0o755)
write(os.path.join(refresh, 'bloom'), '')
run('generate')
bloom = open(os.path.join(packs, 'bloom.md')).read()
check('showing what was read' in bloom and '~/bloom-data-hkjc: on main' in bloom and 'racemate' in bloom, 'an unreachable source lost its last answer')
check(not os.listdir(refresh), 'generate left a refresh request')

if failures:
    print('\n'.join(failures))
    print('\n--- bloom pack ---\n' + texts['bloom'])
    sys.exit(1)
print('context packs: all checks passed\n\n--- bloom pack ---\n' + texts['bloom'])
