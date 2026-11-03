"""Butler's way onto Aaron's kanban board, which runs on pilot.

The board listens on pilot's loopback alone, so every call goes over ssh
as Aaron, with butler's Mac key, and curl posts it to the board's
Butler endpoint there. `kanban self-fixes` also builds the list of
butler's self-fixes from spike's own records and sends it, which is how
`butler-kanban-sync` keeps a card per self-fix on the board.
"""
import json
import os
import re
import subprocess
import sys
import time

HOST = json.loads('@host@')
SSH = '@ssh@'
SELF_FIX = '@selfFix@'
PORT = 7420
ID = re.compile(r'^[0-9]{8}-[0-9]{6}-[0-9]+$')
TOOL = re.compile(r'^[a-z_]{1,64}$')
LINK = re.compile(r'https://claude\.ai/code/session_[A-Za-z0-9]+')
WEEK = 7 * 24 * 3600
MAX_FIXES = 50

USAGE = '''usage: kanban <tool> (its arguments as a JSON object on stdin, or nothing for none) | kanban self-fixes
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
        if os.path.exists(os.path.join(SELF_FIX, 'watch', fix)):
            entry['watching'] = True
        fixes.append(entry)
    return fixes


def main(argv):
    if len(argv) != 2 or not TOOL.match(argv[1].replace('-', '_')):
        print(USAGE, file=sys.stderr)
        return 2
    tool = argv[1].replace('-', '_')
    if tool == 'self_fixes':
        args = {'fixes': self_fixes()}
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
        print(reply.get('text', ''))
        return 0
    print('kanban: %s' % reply.get('error', 'the board refused'), file=sys.stderr)
    return 1


if __name__ == '__main__':
    sys.exit(main(sys.argv))
