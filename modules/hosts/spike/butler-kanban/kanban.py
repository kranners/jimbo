"""Butler's way onto Aaron's kanban board, which runs on pilot.

The board listens on pilot's loopback alone, so every call goes over ssh
as Aaron, with butler's Mac key, and curl posts it to the board's
Butler endpoint there. `kanban self-fixes` also builds the list of
butler's self-fixes from spike's own records and sends it, which is how
`butler-kanban-sync` keeps a card per self-fix on the board, and reads
back what Aaron did to those cards there: a card he closed asks spike to
archive the fix, one he marked done stops it being reported as needing
him. Only those recorded board actions act; nothing in a card's text does.
"""
import json
import os
import pwd
import re
import subprocess
import sys
import time

HOST = json.loads('@host@')
SSH = '@ssh@'
SELF_FIX = '@selfFix@'
BOARD = '@board@'
SPOOL_USER = '@spoolUser@'
# Spike collects the board's messages this often; the board calls spike unreachable after 20 s without.
RELAY_EVERY = 3
MESSAGE_ID = re.compile(r'^[A-Za-z0-9-]{1,64}$')
PORT = 7420
ID = re.compile(r'^[0-9]{8}-[0-9]{6}-[0-9]+$')
TOOL = re.compile(r'^[a-z_]{1,64}$')
LINK = re.compile(r'https://claude\.ai/code/session_[A-Za-z0-9]+')
WEEK = 7 * 24 * 3600
MAX_FIXES = 50
# A fix still open whose progress is older than this is read again, so a card never sticks on a state its session has left.
STALE = 30 * 60
ENDED = ('finished', 'archived', 'failed to start')

USAGE = '''usage: kanban <tool> (its arguments as a JSON object on stdin, or nothing for none) | kanban self-fixes | kanban board-relay
tools: board_snapshot, read_transcript, board_history, put_card, close_card, note, watch, look, arrange,
put_sticker, delete_annotations, find_stickers, create_region, update_region, delete_region,
ask_session, send_prompt, announce, answer_prompt, start_session, finish_session'''


class Unreachable(Exception):
    pass


def ssh_args():
    key = os.path.join(os.environ.get('CREDENTIALS_DIRECTORY', ''), 'butler-mac-key')
    options = [
        '-i', key,
        '-o', 'IdentitiesOnly=yes',
        '-o', 'BatchMode=yes',
        '-o', 'StrictHostKeyChecking=accept-new',
        '-o', 'ConnectTimeout=5',
    ]
    control = os.environ.get('KANBAN_CONTROL_DIR')
    if control:
        # The relay polls every few seconds, so it keeps one connection open.
        options += [
            '-o', 'ControlMaster=auto',
            '-o', 'ControlPath=' + os.path.join(control, 'ssh-%C'),
            '-o', 'ControlPersist=120',
            '-o', 'ServerAliveInterval=10',
        ]
    known = os.environ.get('KANBAN_KNOWN_HOSTS')
    if known:
        options += ['-o', 'UserKnownHostsFile=' + known]
    return [SSH, *options, '%s@%s' % (HOST['user'], HOST['address'])]


def call(tool, args):
    """Posts one tool call to the board on pilot and returns its reply."""
    remote = (
        'curl --silent --show-error --max-time 60 '
        '--header "content-type: application/json" --data-binary @- '
        'http://127.0.0.1:%d/api/butler/tools/%s' % (PORT, tool)
    )
    try:
        result = subprocess.run(
            ssh_args() + [remote], input=json.dumps(args),
            capture_output=True, text=True, timeout=90,
        )
    except subprocess.TimeoutExpired:
        raise Unreachable('the board on pilot did not answer in 90 s')
    if result.returncode == 255:
        raise Unreachable('pilot is unreachable over ssh: %s' % (result.stderr.strip() or 'no answer'))
    if result.returncode != 0:
        raise Unreachable('the board on pilot is not answering: %s' % (result.stderr.strip() or 'curl exited %d' % result.returncode))
    try:
        reply = json.loads(result.stdout)
    except ValueError:
        raise Unreachable('the board answered with something other than JSON: %s' % result.stdout[:300])
    return reply


def read(path):
    try:
        with open(path) as f:
            return f.read()
    except OSError:
        return None


def field(text, name):
    for line in (text or '').splitlines():
        if line.startswith(name + ': '):
            return line[len(name) + 2:]
    return None


def summary_of(progress):
    """The final summary once there is one, else the branch and the latest steps."""
    if not progress:
        return None
    lines = progress.splitlines()
    for line in lines:
        if line.startswith('Final summary'):
            return line.split(': ', 1)[-1][:4000]
    steps = [line for line in lines if line.startswith('- ')][-4:]
    branch = [line for line in lines if line.startswith('Branch: ')]
    return '\n'.join(branch + steps)[:4000] or None


def record(fix):
    """What was done to a fix from the board or by `self-fix archive`, as a state."""
    if os.path.exists(os.path.join(SELF_FIX, 'archived', fix)):
        return 'archived'
    if os.path.exists(os.path.join(SELF_FIX, 'archive', fix)):
        return 'archive requested'
    if os.path.exists(os.path.join(SELF_FIX, 'dismissed', fix)):
        return 'dismissed on the board'
    return None


def refresh_if_stale(fix, now):
    progress = os.path.join(SELF_FIX, 'progress', fix)
    try:
        stale = now - os.stat(progress).st_mtime > STALE
    except OSError:
        stale = True
    if stale:
        touch(os.path.join(SELF_FIX, 'refresh', fix), '')


def touch(path, text):
    try:
        with open(path, 'w') as f:
            f.write(text)
    except OSError as error:
        print('kanban: could not write %s: %s' % (path, error), file=sys.stderr)


def apply_board_actions(text, known):
    """Acts on the cards Aaron closed or marked done, from the reply's Board actions line."""
    line = next((line for line in text.splitlines() if line.startswith('Board actions: ')), None)
    if line is None:
        return text
    try:
        asked = json.loads(line[len('Board actions: '):])
    except ValueError:
        asked = {}
    stamp = time.strftime('%a %-d %b %H:%M')
    applied = []
    for fix in asked.get('archive', []) if isinstance(asked, dict) else []:
        if isinstance(fix, str) and fix in known and record(fix) not in ('archived', 'archive requested'):
            touch(os.path.join(SELF_FIX, 'archive', fix), 'board')
            if os.path.exists(os.path.join(SELF_FIX, 'sessions', fix)):
                touch(os.path.join(SELF_FIX, 'refresh', fix), '')
            applied.append('archiving ' + fix)
    for fix in asked.get('dismiss', []) if isinstance(asked, dict) else []:
        if isinstance(fix, str) and fix in known and record(fix) is None:
            touch(os.path.join(SELF_FIX, 'dismissed', fix), 'Dismissed on the board %s.\n' % stamp)
            try:
                os.remove(os.path.join(SELF_FIX, 'watch', fix))
            except OSError:
                pass
            applied.append('dismissed ' + fix)
    kept = [other for other in text.splitlines() if other != line]
    if applied:
        kept.append('From the board: ' + ', '.join(applied))
    return '\n'.join(kept)


def self_fixes():
    """Every self-fix of the last 7 days, as `self-fix list` reads them."""
    sessions = os.path.join(SELF_FIX, 'sessions')
    queue = os.path.join(SELF_FIX, 'queue')
    now = time.time()
    ids = set()
    for directory in (sessions, queue):
        try:
            names = os.listdir(directory)
        except OSError:
            continue
        for name in names:
            fix = name[:-5] if name.endswith('.json') else name
            try:
                fresh = now - os.stat(os.path.join(directory, name)).st_mtime < WEEK
            except OSError:
                continue
            if ID.match(fix) and fresh:
                ids.add(fix)
    fixes = []
    for fix in sorted(ids, reverse=True)[:MAX_FIXES]:
        started = read(os.path.join(sessions, fix))
        progress = read(os.path.join(SELF_FIX, 'progress', fix))
        entry = {'id': fix}
        if started is None:
            entry['state'] = 'still starting'
        elif not started.startswith('Started '):
            entry['state'] = 'failed to start'
            entry['summary'] = started.strip()[:4000]
        else:
            entry['state'] = field(progress, 'State') or 'unknown, its progress could not be read yet'
            link = LINK.search(started)
            if link:
                entry['link'] = link.group(0)
            summary = summary_of(progress)
            if summary:
                entry['summary'] = summary
        title = field(progress, 'Title')
        if title and title != 'untitled':
            entry['title'] = title[:200]
        entry['state'] = entry['state'][:200]
        closed = record(fix)
        if closed:
            entry['state'] = closed
        elif started and started.startswith('Started ') and not entry['state'].startswith(ENDED):
            refresh_if_stale(fix, now)
        if not closed and os.path.exists(os.path.join(SELF_FIX, 'watch', fix)):
            entry['watching'] = True
        fixes.append(entry)
    return fixes


def write_spool(path, data, owner):
    """Writes a JSON file under a temporary name and renames it into place, for the daemon to read."""
    temp = path + '.tmp'
    with open(temp, 'w') as f:
        json.dump(data, f)
    os.chmod(temp, 0o600)
    if owner is not None:
        os.chown(temp, owner.pw_uid, owner.pw_gid)
    os.rename(temp, path)


def relay_once(owner):
    """Moves the board's queued messages into butler's spool, then Butler's answers back to the board."""
    inbox = os.path.join(BOARD, 'inbox')
    outbox = os.path.join(BOARD, 'outbox')
    reply = call('board_inbox', {})
    if not reply.get('ok'):
        raise Unreachable('the board refused board_inbox: %s' % reply.get('error', 'no reason'))
    messages = json.loads(reply.get('text') or '{}').get('messages', [])
    taken = []
    for message in messages:
        if not isinstance(message, dict) or not MESSAGE_ID.match(str(message.get('id', ''))):
            continue
        write_spool(os.path.join(inbox, message['id'] + '.json'), message, owner)
        taken.append(message['id'])
    if taken:
        call('board_ack', {'ids': taken})
        print('kanban: handed butler %d board message%s' % (len(taken), '' if len(taken) == 1 else 's'))
    try:
        answers = sorted(name for name in os.listdir(outbox) if name.endswith('.json'))
    except OSError:
        answers = []
    for name in answers:
        path = os.path.join(outbox, name)
        try:
            with open(path) as f:
                answer = json.load(f)
        except (OSError, ValueError) as error:
            print('kanban: set aside %s: %s' % (name, error), file=sys.stderr)
            os.rename(path, path + '.rejected')
            continue
        sent = call('board_reply', {
            'thread': str(answer.get('thread', '')),
            'message': str(answer.get('id', '')),
            'text': str(answer.get('text', '')) or '(no answer)',
            'ok': answer.get('ok') is not False,
        })
        if sent.get('ok'):
            os.remove(path)
        else:
            print('kanban: the board refused an answer, setting it aside: %s' % sent.get('error'), file=sys.stderr)
            os.rename(path, path + '.rejected')


def board_relay():
    """Runs for good, relaying every few seconds, and waits out pilot sleeping or the board stopping."""
    owner = pwd.getpwnam(SPOOL_USER) if SPOOL_USER else None
    last = None
    while True:
        try:
            relay_once(owner)
            if last is not None:
                print('kanban: the board is back')
            last = None
        except Unreachable as error:
            if str(error) != last:
                print('kanban: %s; retrying' % error, file=sys.stderr)
            last = str(error)
            time.sleep(RELAY_EVERY * 4)
            continue
        sys.stdout.flush()
        time.sleep(RELAY_EVERY)


def main(argv):
    if len(argv) != 2 or not TOOL.match(argv[1].replace('-', '_')):
        print(USAGE, file=sys.stderr)
        return 2
    tool = argv[1].replace('-', '_')
    # Only the relay's unit carries board messages; Butler's own calls never see or answer the queue.
    if tool.startswith('board_') and tool != 'board_snapshot' and tool != 'board_history' and not os.environ.get('KANBAN_RELAY'):
        print('kanban: %s belongs to the board relay alone' % tool, file=sys.stderr)
        return 2
    if tool == 'board_relay':
        board_relay()
        return 0
    if tool == 'self_fixes':
        args = {'fixes': self_fixes()}
        known = {fix['id'] for fix in args['fixes']}
    else:
        raw = '' if sys.stdin is None or sys.stdin.isatty() else sys.stdin.read()
        try:
            args = json.loads(raw) if raw.strip() else {}
        except ValueError as error:
            print('kanban: the arguments on stdin are not JSON: %s' % error, file=sys.stderr)
            return 2
        if not isinstance(args, dict):
            print('kanban: the arguments on stdin must be a JSON object', file=sys.stderr)
            return 2
    try:
        reply = call(tool, args)
    except Unreachable as error:
        print('kanban: %s' % error, file=sys.stderr)
        return 75
    if reply.get('ok'):
        text = reply.get('text', '')
        if tool == 'self_fixes':
            text = apply_board_actions(text, known)
        print(text)
        return 0
    print('kanban: %s' % reply.get('error', 'the board refused'), file=sys.stderr)
    return 1


if __name__ == '__main__':
    sys.exit(main(sys.argv))
