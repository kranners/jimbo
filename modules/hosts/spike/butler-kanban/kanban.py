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
`kanban safe-sweep`, for `butler-kanban-safe-prompts`, has the board approve
every open prompt its classifier calls safe and audits each approval to
audit/kanban in butler's memory. `kanban threads`, for `butler-kanban-threads`,
sends the daemon's thread cards file to the board, one Butler card per
thread, its events and approvals only while the board runs on spike.
"""
import fcntl
import json
import os
import pwd
import re
import stat
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
# Commits the lines spooled for audit/kanban to butler's memory, as mac's and the reminders' trails are.
MEMORY_AUDIT = '@memoryAudit@'
# The sweep runs as root, so it drops to butler to write this spool in butler's home and run memory-audit on it.
AUDIT_SPOOL = '@auditSpool@'
# The sweep's last run and today's approvals, which the Desk view and Butler read.
SWEEP_STATUS = os.environ.get('KANBAN_SWEEP_STATUS', '/var/lib/butler-kanban/safe-sweep.json')
# How long the root sweep waits for memory-audit, behind the memory's lock, before leaving the lines spooled.
AUDIT_WAIT = 60
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
# A Discord thread id, as the daemon names threads in BUTLER_THREAD_ID and its thread cards file.
THREAD = re.compile(r'^[0-9]{5,25}$')
# The daemon's thread cards, which `kanban threads` sends to the board.
THREAD_CARDS = os.environ.get('KANBAN_THREAD_CARDS', '/var/lib/butler/.claude/channels/discord/thread-cards.json')
# The daemon rewrites the file every minute at least, so one older than this is a daemon that stopped.
THREAD_CARDS_STALE = 10 * 60
# The daemon lists at most 60 threads, each with 30 events of at most 1200 characters, so a file past these is not its.
THREAD_CARDS_BYTES = 8 * 1024 * 1024
THREAD_CARDS_MAX = 80

USAGE = '''usage: kanban <tool> (its arguments as a JSON object on stdin, or nothing for none) | kanban changes | kanban board-relay | kanban safe-sweep | kanban threads
tools: board_snapshot, read_transcript, board_history, put_card, close_card, note, watch, look, arrange, tidy,
put_sticker, delete_annotations, find_stickers, create_region, update_region, delete_region,
ask_session, send_prompt, announce, answer_prompt, approve_safe_prompts, start_session, finish_session'''


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


def call(tool, args, timeout=60, grace=None):
    """Posts one tool call to the board, on spike once cut over, else on pilot, and returns its reply.

    grace is how long ssh may take past curl's own limit, by default up to half a minute.
    """
    timeout = max(1, int(timeout))
    if os.path.exists(HUB_MARKER):
        return call_local(tool, args, timeout)
    remote = (
        'curl --silent --show-error --max-time %d '
        '--header "content-type: application/json" --data-binary @- '
        'http://127.0.0.1:%d/api/butler/tools/%s' % (timeout, PORT, tool)
    )
    # ssh's own connection gets up to half a minute past curl's limit, as a 60 s call always had.
    waited = timeout + (min(30, timeout // 2) if grace is None else grace)
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


def thread_of(fix):
    """The Discord thread a change was asked in: the launcher's record once it started, else its queued request's."""
    thread = (read(os.path.join(SELF_FIX, 'threads', fix)) or '').strip()
    if not thread:
        try:
            with open(os.path.join(SELF_FIX, 'queue', fix + '.json')) as f:
                queued = json.load(f)
        except (OSError, ValueError):
            queued = {}
        thread = str(queued.get('thread') or '') if isinstance(queued, dict) else ''
    return thread if THREAD.match(thread) else None


def mtime_ms(path):
    try:
        return int(os.stat(path).st_mtime * 1000)
    except OSError:
        return None


def times_of(fix, state):
    """When a change started and, once it ended, when and how, for the board's archive."""
    times = {}
    started = mtime_ms(os.path.join(SELF_FIX, 'sessions', fix)) or mtime_ms(os.path.join(SELF_FIX, 'queue', fix + '.json'))
    if started:
        times['startedAt'] = started
    lowered = state.lower()
    if lowered.startswith(ENDED) or lowered.startswith(('archive', 'dismissed')):
        finished = max(filter(None, [mtime_ms(os.path.join(SELF_FIX, d, fix)) for d in ('progress', 'archived', 'archive', 'dismissed')]), default=None)
        if finished:
            times['finishedAt'] = finished
        if lowered.startswith(('finished with an error', 'failed')):
            times['outcome'] = 'failed'
        elif lowered.startswith('finished'):
            times['outcome'] = 'done'
    return times


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
        thread = thread_of(fix)
        if thread:
            entry['thread'] = thread
        entry.update(times_of(fix, entry['state']))
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


# Board questions: a session on the board waiting on an AskUserQuestion is
# read once per waiting state with answer_prompt and no reply, which only shows
# the prompt, and handed to the daemon's question spool, which asks Aaron with
# buttons in his DM; his answer comes back in questions/answers and goes to the
# session with answer_prompt and the prompt id the board gave. Only his own
# clicks write an answer, and only the relay reads or answers board questions.
QUESTIONS_EVERY = 15
ASKS = re.compile(r' asks:$')
QUESTION_LINE = re.compile(r'^(\d+)\. (?:\[([^\]]*)\] )?(.*) \((any of|one of), or a free-text answer\)$')
OPTION_LINE = re.compile(r'^   - "(.*?)"(?:: (.*))?$')
PROMPT_ID = re.compile(r'^Prompt id: ([A-Za-z0-9_-]{1,64})$')
QUESTION_ID = re.compile(r'[^A-Za-z0-9_-]')


def clip(text, limit):
    text = re.sub(r'\s+', ' ', str(text or '')).strip()
    return text if len(text) <= limit else text[:limit - 1] + '\u2026'


def parse_question(text):
    """The questions and prompt id answer_prompt shows for an AskUserQuestion, or None for a permission prompt or anything else."""
    lines = str(text or '').splitlines()
    start = next((i for i, line in enumerate(lines) if ASKS.search(line)), None)
    if start is None:
        return None
    questions, prompt = [], None
    for line in lines[start + 1:]:
        found = PROMPT_ID.match(line)
        if found:
            prompt = found.group(1)
            break
        found = QUESTION_LINE.match(line)
        if found:
            questions.append({'question': found.group(3), 'header': found.group(2) or '', 'multiSelect': found.group(4) == 'any of', 'options': []})
            continue
        found = OPTION_LINE.match(line)
        if found and questions:
            questions[-1]['options'].append({'label': found.group(1), 'description': found.group(2) or ''})
    questions = [q for q in questions if q['options']][:4]
    if not prompt or not questions:
        return None
    return {'prompt': prompt, 'questions': questions}


def shown_questions(parsed):
    """The questions as the daemon's spool takes them, clipped to its limits."""
    out = []
    for q in parsed['questions']:
        shown = {'question': clip(q['question'], 300), 'options': [], 'multiSelect': q['multiSelect']}
        if q['header']:
            shown['header'] = clip(q['header'], 40)
        for option in q['options'][:24]:
            item = {'label': clip(option['label'], 80)}
            if option['description']:
                item['description'] = clip(option['description'], 100)
            shown['options'].append(item)
        out.append(shown)
    return out


def question_dirs(owner):
    base = os.path.join(BOARD, 'questions')
    for sub in ('', 'pending', 'answers', 'posted'):
        path = os.path.join(base, sub)
        if not os.path.isdir(path):
            os.makedirs(path, mode=0o700, exist_ok=True)
            if owner is not None:
                os.chown(path, owner.pw_uid, owner.pw_gid)
    return base


def original_answers(answers, parsed):
    """Aaron's answers with each pick put back to the session's own label, which the board matches exactly."""
    out = []
    for at, answer in enumerate(answers):
        options = parsed['questions'][at]['options'] if at < len(parsed['questions']) else []
        by_shown = {clip(o['label'], 80): o['label'] for o in options}
        reply = {'selected': [by_shown.get(label, label) for label in answer.get('selected') or []][:16]}
        if answer.get('other'):
            reply['other'] = str(answer['other'])[:4000]
        out.append(reply)
    return out


def questions_once(owner, state):
    """Hands back Aaron's answers, then finds the board questions waiting on him and spools the new ones."""
    base = question_dirs(owner)
    answers_dir = os.path.join(base, 'answers')
    for name in sorted(n for n in os.listdir(answers_dir) if n.endswith('.json')):
        path = os.path.join(answers_dir, name)
        try:
            with open(path) as f:
                answer = json.load(f)
        except (OSError, ValueError) as error:
            print('kanban: set aside answer %s: %s' % (name, error), file=sys.stderr)
            os.rename(path, path + '.rejected')
            continue
        qid = str(answer.get('id', ''))
        known = state['asked'].get(qid)
        if not known:
            print('kanban: dropped an answer to a question this relay did not ask: %s' % qid, file=sys.stderr)
            os.remove(path)
            continue
        sent = call('answer_prompt', {
            'session': known['session'], 'prompt': known['prompt'],
            'answers': original_answers(answer.get('answers') or [], known['parsed']),
        })
        if sent.get('ok'):
            print('kanban: answered %s\'s question on the board' % known['name'])
        else:
            print('kanban: the board refused an answer to %s: %s' % (known['name'], sent.get('error')), file=sys.stderr)
        os.remove(path)
        state['answered'].add(qid)
        note = state['notes'].pop(qid, None)
        if note:
            call('delete_annotations', {'ids': [note]})
    snapshot = parse_snapshot(call('board_snapshot', {}))
    if snapshot is None:
        return
    waiting = {}
    current = set()
    for session in snapshot.get('sessions') or []:
        if not isinstance(session, dict) or session.get('activity') != 'needs-you' or not session.get('id'):
            continue
        key = (str(session['id']), str(session.get('needs') or ''))
        current.add(key)
        if key not in state['read']:
            # One read per waiting state, so Butler's cursor visits the session once, not every pass.
            shown = call('answer_prompt', {'session': key[0]})
            state['read'][key] = parse_question(shown.get('text')) if shown.get('ok') else None
        parsed = state['read'][key]
        if parsed:
            qid = QUESTION_ID.sub('-', 'b-%s-%s' % (key[0], parsed['prompt']))[:96]
            waiting[qid] = {'session': key[0], 'name': clip(session.get('name') or key[0], 200), 'prompt': parsed['prompt'], 'parsed': parsed}
    # Reads of states no session is in any more are forgotten, so a session waiting again is read again.
    state['read'] = {k: v for k, v in state['read'].items() if k in current}
    for qid, item in waiting.items():
        if qid in state['asked'] or qid in state['answered']:
            continue
        write_spool(os.path.join(base, 'pending', qid + '.json'), {
            'id': qid, 'session': item['session'], 'sessionName': item['name'],
            'prompt': item['prompt'], 'questions': shown_questions(item['parsed']),
        }, owner)
        state['asked'][qid] = item
        print('kanban: asked Aaron %s\'s question from the board' % item['name'])
    write_spool(os.path.join(base, 'open.json'), {'ids': sorted(waiting)}, owner)
    for qid in [q for q in state['asked'] if q not in waiting]:
        state['asked'].pop(qid, None)
        note = state['notes'].pop(qid, None)
        if note:
            call('delete_annotations', {'ids': [note]})
    state['answered'] &= set(waiting)
    posted_dir = os.path.join(base, 'posted')
    for name in sorted(n for n in os.listdir(posted_dir) if n.endswith('.json')):
        path = os.path.join(posted_dir, name)
        try:
            with open(path) as f:
                posted = json.load(f)
        except (OSError, ValueError):
            posted = {}
        os.remove(path)
        qid = str(posted.get('id', ''))
        link = str(posted.get('link', ''))
        known = state['asked'].get(qid)
        if not known or qid in state['notes'] or not re.match(r'^https://discord\.com/channels/[0-9@me/]+$', link):
            continue
        pinned = call('note', {'target': known['session'], 'text': 'Question for Aaron, waiting in Discord: %s' % link})
        found = re.search(r'\(id ([^)]+)\)', str(pinned.get('text') or ''))
        if found:
            state['notes'][qid] = found.group(1)


def board_relay():
    """Runs for good, relaying every few seconds, and waits out pilot sleeping or the board stopping."""
    owner = pwd.getpwnam(SPOOL_USER) if SPOOL_USER else None
    last = None
    questions = {'asked': {}, 'answered': set(), 'read': {}, 'notes': {}, 'at': 0}
    while True:
        try:
            relay_once(owner)
            if time.time() - questions['at'] >= QUESTIONS_EVERY:
                questions['at'] = time.time()
                try:
                    questions_once(owner, questions)
                except Unreachable:
                    raise
                except Exception as error:  # A bad question never stops the relay carrying messages.
                    print('kanban: the board questions pass failed: %s' % error, file=sys.stderr)
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
# ssh's slack past curl's limit on each forced call, counted inside the budget.
FORCE_GRACE = 3
# Control characters, line and paragraph separators and bidirectional overrides.
CONTROL = re.compile('[\x00-\x09\x0b-\x1f\x7f-\x9f\u2028\u2029\u200e\u200f\u202a-\u202e\u2066-\u2069]')
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
        return min(cap, FORCE_BUDGET - FINISH_RESERVE - FORCE_GRACE - (time.monotonic() - started))

    message = os.environ.get('BUTLER_OWNER_MESSAGE_ID', '')
    words = os.environ.get('BUTLER_OWNER_WORDS', '')
    if not OWNER_MESSAGE.match(message) or not words.strip():
        print("kanban: finish_session with force needs Aaron's own message asking for it, which only the daemon passes; without it, finish the session without force", file=sys.stderr)
        return 2
    ref = args.get('session')
    snapshot = parse_snapshot(call('board_snapshot', {}, 15, FORCE_GRACE))
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
            transcript = call('read_transcript', {'session': session['id'], 'limit': 40}, left(15), FORCE_GRACE)
            if transcript.get('ok'):
                said = last_said(transcript.get('text', ''))
        except Unreachable:
            pass
    region = done_region(snapshot)
    box = (region or {}).get('drawn') or (region or {}).get('frame')
    if isinstance(box, dict) and left(8) > 2:
        try:
            moved = call('arrange', {'cards': [{'id': session['id'], 'x': box['x'] + 24, 'y': box['y'] + 48}]}, left(8), FORCE_GRACE)
            print('Moved into Done: %s' % (moved.get('text') if moved.get('ok') else 'no, ' + str(moved.get('error'))))
        except (Unreachable, KeyError, TypeError):
            pass
    note = handoff_note(session, said, message)
    print('Hand-off note: %s' % note)
    if left(8) > 2:
        try:
            noted = call('note', {'target': session['id'], 'text': note}, left(8), FORCE_GRACE)
            if not noted.get('ok'):
                print('The board refused the note: %s' % noted.get('error'))
        except Unreachable as error:
            print('The note did not reach the board: %s' % error)
    remaining = FORCE_BUDGET - FORCE_GRACE - (time.monotonic() - started)
    reply = call('finish_session', {'session': session['id'], 'force': True, 'ownerMessage': message}, max(5, remaining), FORCE_GRACE)
    if reply.get('ok'):
        print('Board: %s' % reply.get('text', ''))
        return 0
    print('kanban: %s; the hand-off note stays on the card, but the session was not finished' % reply.get('error', 'the board refused'), file=sys.stderr)
    return 1


# The safe sweep: approve_safe_prompts approves, on every session waiting on
# Aaron, each open prompt the board's classifier calls safe, and leaves the
# rest, the guardrails, for him. Each approval it reports becomes one line of
# audit/kanban in butler's memory.
SUMMARY = re.compile(r'^Approved (\d+), left (\d+) for Aaron\b')
# The board reports each approval as `<session>: approved <title> (<tool>, request <id>)`.
APPROVED = re.compile(r': approved ')
BULLET = re.compile(r'^[\s\-*\u2022\u2713\u2714]+')


def approvals_of(reply):
    """One line per prompt the board approved: its structured list when it sends one, else its report's Approved lines."""
    listed = reply.get('approved')
    if isinstance(listed, list) and listed:
        lines = []
        for item in listed:
            if isinstance(item, dict):
                lines.append('session %s, tool %s, request %s%s' % (
                    item.get('session') or '?', item.get('tool') or '?',
                    item.get('requestId') or item.get('request') or item.get('prompt') or '?',
                    ', "%s"' % item['title'] if item.get('title') else ''))
            else:
                lines.append(str(item))
        return [clean(line, 400) for line in lines]
    found, summary, heading = [], None, ''
    for line in str(reply.get('text') or '').splitlines():
        bare = BULLET.sub('', line).strip()
        match = SUMMARY.match(bare)
        if match:
            summary = int(match.group(1))
            continue
        bullet = bare != line.strip()
        if not bullet:
            # A line of its own heads the bulleted prompts under it, as a session's name does.
            heading = bare
        if APPROVED.search(bare):
            found.append(clean('%s: %s' % (heading, bare) if bullet and heading else bare, 400))
    if summary and not found:
        # The report named no prompt line by line, so the count alone is kept, never nothing.
        found.append('%d prompt%s, the board listing none by name' % (summary, '' if summary == 1 else 's'))
    return found


def audit_lines(approvals, who='safe-sweep', now=None):
    """The spool lines memory-audit takes, `YYYY-MM-DD<tab><line>`, one per approval."""
    now = time.localtime() if now is None else now
    day = time.strftime('%Y-%m-%d', now)
    stamp = time.strftime('%H:%M:%S %z', now)
    return ['%s\t%s %s approved, safe set: %s' % (day, stamp, who, line) for line in approvals]


def append_audit(lines):
    """Appends the lines to the spool, under its lock, as whoever runs it."""
    os.makedirs(os.path.dirname(AUDIT_SPOOL), mode=0o700, exist_ok=True)
    with open(AUDIT_SPOOL, 'a') as spool:
        fcntl.flock(spool, fcntl.LOCK_EX)
        spool.write(''.join(line + '\n' for line in lines))


def audit_as(owner, lines):
    """As root, spools the lines and commits them as butler, in a child that has dropped to butler first.

    The spool lives in butler's home, so root never opens or chowns a path butler controls, which a symlink
    there would turn into a write anywhere. memory-audit runs to the end here rather than in the background,
    since a oneshot unit's leftover processes are killed once it exits; lines it has no time for stay spooled
    for its next run.
    """
    pid = os.fork()
    if pid == 0:
        status = 1
        try:
            os.initgroups(owner.pw_name, owner.pw_gid)
            os.setgid(owner.pw_gid)
            os.setuid(owner.pw_uid)
            os.environ['HOME'] = owner.pw_dir
            os.chdir(owner.pw_dir)
            append_audit(lines)
            status = 0
            subprocess.run([MEMORY_AUDIT, 'kanban', AUDIT_SPOOL], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                           stderr=subprocess.DEVNULL, timeout=AUDIT_WAIT)
        except subprocess.TimeoutExpired:
            pass
        except (OSError, subprocess.SubprocessError) as error:
            print('kanban: could not write the audit lines: %s' % error, file=sys.stderr)
        finally:
            sys.stderr.flush()
            os._exit(status)
    _, status = os.waitpid(pid, 0)
    return os.WIFEXITED(status) and os.WEXITSTATUS(status) == 0


def audit(lines):
    """Spools the lines for audit/kanban as butler's and has memory-audit commit them; never fails the sweep."""
    if not lines:
        return
    try:
        if os.getuid() == 0:
            audit_as(pwd.getpwnam(SPOOL_USER), lines)
            return
        append_audit(lines)
        subprocess.Popen([MEMORY_AUDIT, 'kanban', AUDIT_SPOOL], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL, start_new_session=True)
    except (OSError, KeyError) as error:
        print('kanban: could not write the audit lines: %s' % error, file=sys.stderr)


def thread_tag():
    """The thread a call of Butler's came from, as the daemon names it, for the audit line."""
    ident = re.sub(r'[^0-9A-Za-z_-]', '', os.environ.get('BUTLER_THREAD_ID', ''))[:32]
    if not ident:
        return ''
    title = clean(' '.join(os.environ.get('BUTLER_THREAD_TITLE', '').split()), 60).replace('"', "'")
    return ' [thread %s%s]' % (ident, ' "%s"' % title if title else '')


def approved_count(reply, approvals):
    """How many prompts the board approved: its summary line's count, else one per approval line."""
    for line in str(reply.get('text') or '').splitlines():
        match = SUMMARY.match(BULLET.sub('', line).strip())
        if match:
            return int(match.group(1))
    listed = reply.get('approved')
    return len(listed) if isinstance(listed, list) else len(approvals)


def sweep_status(result, approved=0, path=None, now=None):
    """Records the sweep's last run and the prompts it approved today, for the Desk view and Butler.

    The file is the sweep's own, in its state directory, replaced whole, and holds counts and times alone.
    """
    path = path or SWEEP_STATUS
    now = time.time() if now is None else now
    day = time.strftime('%Y-%m-%d', time.localtime(now))
    try:
        with open(path) as handle:
            before = json.load(handle)
    except (OSError, ValueError):
        before = {}
    today = before.get('approvedToday', 0) if before.get('day') == day else 0
    status = {
        'lastSweep': time.strftime('%Y-%m-%dT%H:%M:%S%z', time.localtime(now)),
        'lastSweepEpoch': int(now),
        'lastResult': result,
        'lastApproved': approved,
        'day': day,
        'approvedToday': (today if isinstance(today, int) else 0) + approved,
    }
    try:
        partial = path + '.partial'
        with open(partial, 'w') as handle:
            json.dump(status, handle)
        os.chmod(partial, 0o644)
        os.replace(partial, path)
    except OSError as error:
        print('kanban: could not record the sweep: %s' % error, file=sys.stderr)
    return status


def safe_sweep():
    """Approves every safe prompt on the board, prints the board's report, audits each approval and records the run."""
    try:
        reply = call('approve_safe_prompts', {})
    except Unreachable as error:
        print('kanban: %s' % error, file=sys.stderr)
        sweep_status('unreachable')
        return 75
    if not reply.get('ok'):
        error = str(reply.get('error', 'the board refused'))
        if 'Unknown tool' in error:
            # A board older than approve_safe_prompts, such as pilot's while it waits for the move to spike, cannot
            # sweep at all: said once a run and recorded, but no failure, so the failed-unit alert stays for real ones.
            print('kanban: the board runs code older than approve_safe_prompts, so nothing was approved: %s' % error,
                  file=sys.stderr)
            sweep_status('board-too-old')
            return 75
        print('kanban: %s' % error, file=sys.stderr)
        sweep_status('refused')
        return 1
    print(reply.get('text', ''))
    approvals = approvals_of(reply)
    audit(audit_lines(approvals))
    sweep_status('ok', approved_count(reply, approvals) if approvals else 0)
    return 0


def with_parent(args):
    """Ties a session Butler starts to the thread it was started from, from the daemon's own environment.

    The model's own parent, if it gave one, is replaced, so a card's link to a thread is always the daemon's word.
    """
    args = {key: value for key, value in args.items() if key != 'parent'}
    thread = os.environ.get('BUTLER_THREAD_ID', '')
    if not THREAD.match(thread):
        return args
    parent = {'thread': thread}
    title = clean(' '.join(os.environ.get('BUTLER_THREAD_TITLE', '').split()), 100).strip()
    if title:
        parent['title'] = title
    desk = clean(os.environ.get('BUTLER_DESK_SESSION', ''), 40).strip()
    if desk:
        parent['desk'] = desk
    args['parent'] = parent
    return args


def thread_cards(path=None, now=None, on_spike=None):
    """The daemon's thread cards as the board's butler_threads takes them, or None, saying why, when there are none to send.

    The board on pilot, before the cutover, gets each card without its events and approvals, which stay on spike.
    """
    path = path or THREAD_CARDS
    now = time.time() if now is None else now
    on_spike = os.path.exists(HUB_MARKER) if on_spike is None else on_spike
    try:
        # Root reads it from butler's home, so a link there is refused rather than followed, and a runaway file is not read whole.
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
        with os.fdopen(fd, 'rb') as f:
            info = os.fstat(f.fileno())
            if not stat.S_ISREG(info.st_mode):
                raise OSError('it is not a regular file')
            raw = f.read(THREAD_CARDS_BYTES + 1)
        if len(raw) > THREAD_CARDS_BYTES:
            raise OSError('it is over %d bytes' % THREAD_CARDS_BYTES)
        cards = json.loads(raw.decode('utf-8'))
        written = info.st_mtime
    except FileNotFoundError:
        print('kanban: no thread cards at %s yet, so the board is left as it is' % path)
        return None
    except (OSError, ValueError) as error:
        print('kanban: could not read the thread cards at %s: %s' % (path, error), file=sys.stderr)
        return None
    if not isinstance(cards, dict) or not isinstance(cards.get('threads'), list):
        print('kanban: the thread cards at %s hold no threads list' % path, file=sys.stderr)
        return None
    updated = cards.get('updatedAt')
    if isinstance(updated, (int, float)) and not isinstance(updated, bool):
        written = updated / 1000
    if now - written > THREAD_CARDS_STALE:
        print('kanban: the thread cards are %d minutes old, so the daemon is not writing them and the board is left as it is'
              % ((now - written) // 60))
        return None
    threads = [card for card in cards['threads'] if isinstance(card, dict)][:THREAD_CARDS_MAX]
    if not on_spike:
        threads = [dict(card, events=[], approvals=[]) for card in threads]
    return {'threads': threads}


def send_threads():
    """Sends the daemon's thread cards to the board and prints its reply, the cards and the orphan report, for the journal."""
    args = thread_cards()
    if args is None:
        return 0
    try:
        reply = call('butler_threads', args)
    except Unreachable as error:
        print('kanban: %s' % error, file=sys.stderr)
        return 75
    if not reply.get('ok'):
        error = str(reply.get('error', 'the board refused'))
        if 'unknown tool' in error.lower():
            # A board older than butler_threads, such as pilot's while it waits for the move to spike: no failure.
            print('kanban: the board runs code older than butler_threads, so it shows no thread cards: %s' % error,
                  file=sys.stderr)
            return 75
        print('kanban: %s' % error, file=sys.stderr)
        return 1
    print(reply.get('text', ''))
    tidy()
    return 0


def tidy():
    """Has the board archive finished cards and lay out the rest, as Butler's own `kanban tidy` does; a board without tidy is left as it is."""
    try:
        reply = call('tidy', {})
    except Unreachable as error:
        print('kanban: %s' % error, file=sys.stderr)
        return 75
    if not reply.get('ok'):
        print('kanban: tidy: %s' % reply.get('error', 'the board refused'), file=sys.stderr)
        return 75 if 'unknown tool' in str(reply.get('error', '')).lower() else 1
    print(reply.get('text', ''))
    return 0


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
    if tool == 'safe_sweep':
        return safe_sweep()
    # The thread cards come from the daemon's own file, sent by spike's root sync alone, never with Butler's arguments.
    if tool == 'butler_threads':
        print('kanban: butler_threads is sent by `kanban threads` alone, from the daemon\'s thread cards file', file=sys.stderr)
        return 2
    if tool == 'threads':
        return send_threads()
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
    # Only the forced path below sends ownerMessage, from the daemon's own environment, never from Butler's arguments.
    if tool == 'finish_session' and 'ownerMessage' in args and args.get('force') is not True:
        print("kanban: ownerMessage goes only with force, and kanban fills it in from Aaron's own message", file=sys.stderr)
        return 2
    if tool == 'finish_session' and args.get('force') is True:
        try:
            return force_finish(args)
        except Unreachable as error:
            print('kanban: %s' % error, file=sys.stderr)
            return 75
    sent = None
    if tool == 'start_session':
        args = with_parent(args)
    if tool in ('start_session', 'send_prompt'):
        args, sent = with_context(tool, args)
    try:
        reply = call(tool, args)
        if tool == 'start_session' and 'parent' in args and 'Unknown argument parent' in str(reply.get('error', '')):
            # A board older than session parents, such as pilot's while it waits for the move to spike, still starts the session, unlinked.
            args = {key: value for key, value in args.items() if key != 'parent'}
            reply = call(tool, args)
    except Unreachable as error:
        print('kanban: %s' % error, file=sys.stderr)
        return 75
    if reply.get('ok'):
        text = reply.get('text', '')
        if tool == 'self_fixes':
            text = apply_board_actions(text, known)
        print(text)
        if tool == 'approve_safe_prompts' or (tool == 'answer_prompt' and args.get('allow_safe') is True):
            audit(audit_lines(approvals_of(reply), 'butler%s' % thread_tag()))
        if sent:
            print(sent)
        return 0
    print('kanban: %s' % reply.get('error', 'the board refused'), file=sys.stderr)
    return 1


if __name__ == '__main__':
    sys.exit(main(sys.argv))
