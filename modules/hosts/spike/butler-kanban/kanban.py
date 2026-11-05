"""Butler's way onto Aaron's kanban board, on pilot or, once cut over, on spike.

While the board runs on pilot it listens on pilot's loopback alone, so
every call goes over ssh as Aaron, with butler's Mac key, and curl posts
it to the board's Butler endpoint there. Once `kanban-hub cutover` has
moved it to spike, which it marks with HUB_MARKER, every call posts to
spike's own loopback instead. `kanban changes` also builds the list of
butler's changes from spike's own records and sends it, which is how
`butler-kanban-sync` keeps a card per change on the board, and reads
back what Aaron did to those cards there: a card he closed asks spike to
archive the change, one he marked done stops it being reported as needing
him. Only those recorded board actions act; nothing in a card's text does.
"""
import json
import os
import pwd
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request

HOST = json.loads('@host@')
SSH = '@ssh@'
SELF_FIX = '@selfFix@'
BOARD = '@board@'
SPOOL_USER = '@spoolUser@'
# Prints the context pack a prompt to a session starts with, from `context prefix`.
CONTEXT = '@context@'
# Spike collects the board's messages this often; the board calls spike unreachable after 20 s without.
RELAY_EVERY = 3
MESSAGE_ID = re.compile(r'^[A-Za-z0-9-]{1,64}$')
PORT = 7420
# Present once the board runs on spike itself (modules/hosts/spike/kanban.nix).
HUB_MARKER = '@hubMarker@'
ID = re.compile(r'^[0-9]{8}-[0-9]{6}-[0-9]+$')
TOOL = re.compile(r'^[a-z_]{1,64}$')
LINK = re.compile(r'https://claude\.ai/code/session_[A-Za-z0-9]+')
WEEK = 7 * 24 * 3600
MAX_FIXES = 50
# A fix still open whose progress is older than this is read again, so a card never sticks on a state its session has left.
STALE = 30 * 60
ENDED = ('finished', 'archived', 'failed to start')

USAGE = '''usage: kanban <tool> (its arguments as a JSON object on stdin, or nothing for none) | kanban changes | kanban board-relay
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


def call_local(tool, args, timeout=60):
    """Posts one tool call to the board on spike's loopback and returns its reply."""
    request = urllib.request.Request(
        'http://127.0.0.1:%d/api/butler/tools/%s' % (PORT, tool),
        data=json.dumps(args).encode(), headers={'content-type': 'application/json'}, method='POST',
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            body = response.read().decode('utf-8', 'replace')
    except urllib.error.HTTPError as error:
        body = error.read().decode('utf-8', 'replace')
    except (urllib.error.URLError, OSError) as error:
        raise Unreachable('the board on spike is not answering: %s' % getattr(error, 'reason', error))
    try:
        return json.loads(body)
    except ValueError:
        raise Unreachable('the board answered with something other than JSON: %s' % body[:300])


def call(tool, args, timeout=60):
    """Posts one tool call to the board, on spike once cut over, else on pilot, and returns its reply."""
    timeout = max(1, int(timeout))
    if os.path.exists(HUB_MARKER):
        return call_local(tool, args, timeout)
    remote = (
        'curl --silent --show-error --max-time %d '
        '--header "content-type: application/json" --data-binary @- '
        'http://127.0.0.1:%d/api/butler/tools/%s' % (timeout, PORT, tool)
    )
    # ssh's own connection gets up to half a minute past curl's limit, as a 60 s call always had.
    waited = timeout + min(30, timeout // 2)
    try:
        result = subprocess.run(
            ssh_args() + [remote], input=json.dumps(args),
            capture_output=True, text=True, timeout=waited,
        )
    except subprocess.TimeoutExpired:
        raise Unreachable('the board on pilot did not answer in %d s' % waited)
    if result.returncode == 255:
        raise Unreachable('pilot is unreachable over ssh: %s' % (result.stderr.strip() or 'no answer'))
    if result.returncode != 0:
        raise Unreachable('the board on pilot is not answering: %s' % (result.stderr.strip() or 'curl exited %d' % result.returncode))
    try:
        reply = json.loads(result.stdout)
    except ValueError:
        raise Unreachable('the board answered with something other than JSON: %s' % result.stdout[:300])
    return reply


def session_cwd(target):
    """The folder a session on the board works in, for picking its context pack."""
    try:
        reply = call('board_snapshot', {})
    except Unreachable:
        return None
    text = reply.get('text', '') if reply.get('ok') else ''
    start = text.find('{')
    try:
        snapshot = json.JSONDecoder().raw_decode(text[start:])[0] if start >= 0 else {}
    except ValueError:
        return None
    for session in (snapshot.get('sessions') or []) if isinstance(snapshot, dict) else []:
        if isinstance(session, dict) and str(target) in (str(session.get('id')), str(session.get('short'))):
            return session.get('cwd')
    return None


def with_context(tool, args):
    """Puts the matching context pack in front of a session's prompt, so it starts where Aaron and Butler are."""
    field = 'prompt' if tool == 'start_session' else 'text'
    original = args.get(field)
    if not isinstance(original, str) or not original.strip() or original.startswith('Context from Butler:'):
        return args, None
    cwd = args.get('cwd') if tool == 'start_session' else session_cwd(args.get('session'))
    request = {'cwd': cwd, 'text': '%s %s' % (args.get('name') or '', original), 'default': 'board'}
    if tool == 'send_prompt':
        # A running session already has its start's pack, so a later prompt carries a shorter one.
        request['limit'] = 2000
    try:
        block = subprocess.run([CONTEXT, 'prefix'], input=json.dumps(request), capture_output=True, text=True, timeout=20).stdout
    except (OSError, subprocess.TimeoutExpired):
        return args, None
    area = re.search(r"spike's ([a-z]+) pack", block)
    if not area:
        return args, None
    refreshed = re.search(r'^Refreshed (.+?) by spike', block, re.MULTILINE)
    return dict(args, **{field: block + original}), 'Context sent: the %s pack%s, in front of the prompt.' % (
        area.group(1), ', refreshed %s' % refreshed.group(1) if refreshed else '')


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
    """What was done to a change from the board or by `change archive`, as a state."""
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
    """Every change of the last 7 days, as `change list` reads them."""
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


# Force-finishing a session: the daemon runs a forced finish_session only on
# Aaron's own message, which it names in these, and this checks his words
# name the session before it writes a hand-off note and asks the board.
OWNER_MESSAGE = re.compile(r'^[0-9]{15,22}$')
BUSY = ('working', 'watching')
# The daemon's whole command timeout is 60 s, so everything here ends well inside it.
FORCE_BUDGET = 50
FINISH_RESERVE = 15
CONTROL = re.compile(r'[\x00-\x09\x0b-\x1f\x7f-\x9f]')
WORD = re.compile(r"[a-z0-9]+(?:'[a-z]+)?")
# Words too common in session names to say which session he meant.
COMMON = frozenset("""
    a an the and or of to for in on at by with from into via is it its this that these those
    fix fixes add adds update updates make makes new old use run runs check session sessions
    work task change changes bug test tests stuck one two up out off all
""".split())
PLURAL = re.compile(
    r"\b(?:those|these|the|all|both|all\s+of\s+the|all\s+the)\s+(?:[\w-]+\s+){0,2}sessions\b"
    r"|\b(?:all\s+of\s+)?them\b|\bboth(?:\s+of\s+them)?\b"
    r"|\ball\s+(?:of\s+)?the\s+(?:stuck|old|stale|idle|dead|finished|done|failed|stopped)\b",
    re.IGNORECASE,
)


def clean(text, limit=None):
    """Text with control characters, newlines and tabs among them, turned to spaces, cut off at limit."""
    text = CONTROL.sub(' ', str(text or '')).replace('\n', ' ')
    if limit is not None and len(text) > limit:
        text = text[:max(0, limit - 1)].rstrip() + '…'
    return text


def words_of(text):
    return WORD.findall(str(text or '').lower())


def parse_snapshot(reply):
    """The board_snapshot JSON after its first line, or None."""
    text = reply.get('text', '') if reply.get('ok') else ''
    start = text.find('{')
    if start < 0:
        return None
    try:
        snapshot = json.JSONDecoder().raw_decode(text[start:])[0]
    except ValueError:
        return None
    return snapshot if isinstance(snapshot, dict) else None


def find_session(sessions, ref):
    """The session a reference names, by id, short id or exact name, ignoring case, or an id's unique prefix."""
    ref = str(ref or '').strip().lower()
    if not ref:
        return None
    for key in ('id', 'short', 'name'):
        found = [s for s in sessions if str(s.get(key) or '').lower() == ref]
        if len(found) == 1:
            return found[0]
    found = [s for s in sessions if str(s.get('id') or '').lower().startswith(ref)]
    return found[0] if len(found) == 1 and len(ref) >= 6 else None


def distinctive(session, sessions):
    """The words of a session's name that are not common and no other session's name shares."""
    theirs = set()
    for other in sessions:
        if other is not session:
            theirs.update(words_of(other.get('name')))
    return [w for w in dict.fromkeys(words_of(session.get('name'))) if len(w) >= 3 and w not in COMMON and w not in theirs]


def names_session(words, session, sessions):
    """Whether Aaron's words name this session: its id, short id or name, or a plural reference to several."""
    said = str(words or '').lower()
    for key in ('id', 'short'):
        value = str(session.get(key) or '').lower()
        if len(value) >= 6 and value in said:
            return True
    spoken = words_of(said)
    name = words_of(session.get('name'))
    if name and ' %s ' % ' '.join(name) in ' %s ' % ' '.join(spoken):
        return True
    unique = distinctive(session, sessions)
    heard = [w for w in unique if w in spoken]
    if heard and len(heard) * 2 >= len(unique):
        return True
    return bool(PLURAL.search(said))


def last_said(transcript_text, count=3, limit=300):
    """The session's last few assistant messages, from read_transcript's lines."""
    said = []
    for line in (transcript_text or '').splitlines():
        match = re.match(r'^\[[^\]]+\] assistant: (.*)$', line)
        if match and match.group(1).strip():
            said.append(clean(match.group(1), limit).strip())
    return said[-count:]


def unreported(session):
    """What the session was holding when it was ended, from the board's own fields."""
    parts = ['%s was %s' % (clean(session.get('name') or session.get('id'), 200), session.get('activity') or 'in an unknown state')]
    for key, label in (('needs', 'it needed'), ('doing', 'it was doing'), ('goal', 'its goal was')):
        value = session.get(key)
        if value:
            parts.append('%s: %s' % (label, clean(value, 300)))
    return '; '.join(parts)


def handoff_note(session, said, message):
    """One paragraph Butler leaves on the card, so whoever picks the work up knows where it stood."""
    text = "Force-finished on Aaron's message %s. %s; started %s, last active %s, in %s. " % (
        message, unreported(session).rstrip('.'), session.get('startedAt') or 'at an unknown time',
        session.get('updatedAt') or 'at an unknown time', session.get('cwd') or 'an unknown folder')
    if said:
        text += 'Its last words: %s. ' % ' / '.join('"%s"' % s for s in said)
    else:
        text += 'Its transcript could not be read, so its last words are not known. '
    text += 'Anything it had not reported, committed or landed stays in its transcript and its folder, unreviewed.'
    return clean(text, 4000)


def done_region(snapshot):
    for region in snapshot.get('regions') or []:
        if isinstance(region, dict) and str(region.get('name') or '').strip().lower() == 'done':
            return region
    return None


def force_finish(args):
    """finish_session with force: refused unless the daemon passed Aaron's own message naming the session."""
    started = time.monotonic()

    def left(cap):
        return min(cap, FORCE_BUDGET - FINISH_RESERVE - (time.monotonic() - started))

    message = os.environ.get('BUTLER_OWNER_MESSAGE_ID', '')
    words = os.environ.get('BUTLER_OWNER_WORDS', '')
    if not OWNER_MESSAGE.match(message) or not words.strip():
        print("kanban: finish_session with force needs Aaron's own message asking for it, which only the daemon passes; without it, finish the session without force", file=sys.stderr)
        return 2
    ref = args.get('session')
    snapshot = parse_snapshot(call('board_snapshot', {}, 15))
    if snapshot is None:
        print('kanban: could not read the board to find %s' % ref, file=sys.stderr)
        return 1
    sessions = [s for s in snapshot.get('sessions') or [] if isinstance(s, dict)]
    session = find_session(sessions, ref)
    if session is None:
        print('kanban: no session %s on the board; use board_snapshot for ids' % ref, file=sys.stderr)
        return 1
    name = clean(session.get('name') or session.get('id'), 200)
    if session.get('activity') in BUSY:
        print('kanban: %s is %s right now, so it cannot be force-finished; wait until it stops' % (name, session.get('activity')), file=sys.stderr)
        return 1
    if not names_session(words, session, sessions):
        print('kanban: Aaron\'s message %s does not name %s, by its name, id or short id, or as "those sessions", so it is not force-finished; ask him which session he means' % (message, name), file=sys.stderr)
        return 1
    print('Unreported at the end: %s.' % unreported(session))
    said = []
    if left(15) > 2:
        try:
            transcript = call('read_transcript', {'session': session['id'], 'limit': 40}, left(15))
            if transcript.get('ok'):
                said = last_said(transcript.get('text', ''))
        except Unreachable:
            pass
    region = done_region(snapshot)
    box = (region or {}).get('drawn') or (region or {}).get('frame')
    if isinstance(box, dict) and left(8) > 2:
        try:
            moved = call('arrange', {'cards': [{'id': session['id'], 'x': box['x'] + 24, 'y': box['y'] + 48}]}, left(8))
            print('Moved into Done: %s' % (moved.get('text') if moved.get('ok') else 'no, ' + str(moved.get('error'))))
        except (Unreachable, KeyError, TypeError):
            pass
    note = handoff_note(session, said, message)
    print('Hand-off note: %s' % note)
    if left(8) > 2:
        try:
            noted = call('note', {'target': session['id'], 'text': note}, left(8))
            if not noted.get('ok'):
                print('The board refused the note: %s' % noted.get('error'))
        except Unreachable as error:
            print('The note did not reach the board: %s' % error)
    remaining = FORCE_BUDGET - (time.monotonic() - started)
    reply = call('finish_session', {'session': session['id'], 'force': True, 'ownerMessage': message}, max(5, remaining))
    if reply.get('ok'):
        print('Board: %s' % reply.get('text', ''))
        return 0
    print('kanban: %s' % reply.get('error', 'the board refused'), file=sys.stderr)
    return 1


def main(argv):
    if len(argv) != 2 or not TOOL.match(argv[1].replace('-', '_')):
        print(USAGE, file=sys.stderr)
        return 2
    tool = argv[1].replace('-', '_')
    # `changes`, once `self-fixes`, still reaches the board as its tool `self_fixes`, which every board knows.
    if tool == 'changes':
        tool = 'self_fixes'
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
    if tool == 'finish_session' and args.get('force') is True:
        try:
            return force_finish(args)
        except Unreachable as error:
            print('kanban: %s' % error, file=sys.stderr)
            return 75
    sent = None
    if tool in ('start_session', 'send_prompt'):
        args, sent = with_context(tool, args)
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
        if sent:
            print(sent)
        return 0
    print('kanban: %s' % reply.get('error', 'the board refused'), file=sys.stderr)
    return 1


if __name__ == '__main__':
    sys.exit(main(sys.argv))
