

# butler-work: the "Work in flight" snapshot the life explorer shows Aaron.
#
# Appended to builders.py without its main, so it reads the same change records and GitHub
# cache logic. It writes a small JSON file of titles, plain summaries, states, times, the
# parts of Aaron's setup each change touches, how changes overlap, and each Claude account's
# usage. It never writes a brief beyond one plain sentence, a file path, a branch name or
# anything shaped like a secret, and every field is clipped. The explorer escapes it all again.

import calendar  # noqa: E402

WORK_DIR = os.environ.get('WORK_DIRECTORY', '/var/lib/butler-work')
LIMITS_DIR = '@limits@'
DAY = 24 * 3600
REPORT_KEYS = ('Changed', 'Before', 'After', 'Ready', 'Go live', 'Aaron must', 'Commit')
REPORT_LINE = re.compile(r'\b(%s):\s*' % '|'.join(re.escape(k) for k in REPORT_KEYS))
NOTHING = re.compile(r'^(nothing|none|no(thing)? (needed|required)|n/?a)\b', re.I)

# The parts of Aaron's setup, in words he knows, each found from a change's title, brief and files.
AREAS = (
    ('The call voice', r'\b(call|calls|voice|realtime|kokoro|speech|spoken|mic|hand-?off)\b|butler-call|butler-voice|src/discord/call|src/engine/(call|realtime)'),
    ('The kanban board', r'\b(kanban|board)\b|butler-kanban|^kranners/kanban'),
    ('The iPad and iPhone apps', r'\b(ipad|iphone|pwa|pwas|home-screen|testflight|remote desk(top)?)\b|remote-desk|manifest\.webmanifest|sw\.js'),
    ('Your machines', r'\b(mac|macs|macbook|pilot|piggys|jimbo pc|the pc|windows|wake-?on-?lan|hammerspoon)\b|butler-access|butler-mac|hosts/(jimbo|pilot)|windows-'),
    ('The life explorer', r'\b(life explorer|explorer|money dashboard|goals timeline|life index|data index)\b|^kranners/butler:|index/explorer|money/'),
    ('Backlogic', r'\bbacklogic\b'),
    ('Home automation', r'\b(home assistant|framer|panel|lights?|kitchen|wall panel)\b|home-assistant|butler-home|hosts/framer'),
    ('Mail and messages', r'\b(mail|email|inbox|messenger|slack)\b|butler-mail|butler-messenger|butler-slack'),
    ('Landing and deploys', r'\b(landing|landings|deploy|deploys|restarts?)\b|jimbo-switch|butler-land'),
)
AREA_PATTERNS = [(name, re.compile(pattern, re.I | re.M)) for name, pattern in AREAS]
DEFAULT_AREA = 'Butler himself'

PATHISH = re.compile(r'`[^`]*`|\b[\w.-]+/[\w./-]+\b|\b[\w-]+\.(nix|py|ts|js|json|md|sh|ps1)\b|\b[0-9]{8}-[0-9]{6}-[0-9]+\b|https?://\S+')


def plain(text):
    """Turns brief wording into words for Aaron: the change naming, no paths, ids or links."""
    text = PATHISH.sub('', str(text or ''))
    text = re.sub(r'\bself-fix(es)?\b', lambda m: 'changes' if m.group(1) else 'change', text, flags=re.I)
    text = re.sub(r"\bAaron's\b", 'your', text)
    text = re.sub(r'\bAaron\b', 'you', text)
    text = re.sub(r'\b(He|She|They) wants\b', 'You want', text)
    text = re.sub(r'\s+([,.;:])', r'\1', re.sub(r'\(\s*\)', '', text))
    return re.sub(r'\s+', ' ', text).strip(' ,;:')


def capital(text):
    return text if re.match(r'i[A-Z]', text) else text[:1].upper() + text[1:]


def sentences(text):
    return [s.strip() for s in re.split(r'(?<=[.!?])\s+(?=[A-Z"“])', text or '') if s.strip()]


def purpose_of(title, brief):
    """One short plain sentence of what a change is for, from the first paragraph of its brief, or its title."""
    brief = brief or ''
    quoted = re.search(r'in (?:his|their) words:\s*["“](.+?)["”](?:\s|$)', brief, re.S)
    after = brief[quoted.end():] if quoted else re.sub(r"^Aaron's request \([^)]*\)[^:]*:\s*", '', brief)
    for sentence in sentences(after):
        if re.match(r'(He|She|They|Aaron) wants\b|Agreed with (him|them)\b', sentence):
            sentence = re.sub(r'^Agreed with (him|them):\s*', 'Agreed with you: ', sentence)
            return clean(plain(sentence), 180)
    if quoted:
        words = sentences(plain(quoted.group(1)))
        if words:
            return clean('You asked: “%s”' % ' '.join(words)[:170].rstrip(), 180)
    return clean(plain(title) or 'Not described yet', 180)


def report(summary):
    """The Changed:, Before:, After: and other card lines a landed change ends its summary with."""
    found = {}
    marks = list(REPORT_LINE.finditer(summary or ''))
    for mark, following in zip(marks, marks[1:] + [None]):
        value = summary[mark.end():following.start() if following else len(summary)]
        found[mark.group(1)] = value.strip()
    head = summary[:marks[0].start()] if marks else (summary or '')
    return head.strip(), found


def stamp_of(fix):
    try:
        return int(time.mktime(time.strptime(fix[:15], '%Y%m%d-%H%M%S')))
    except ValueError:
        return None


def utc_seconds(text):
    match = re.match(r'(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d)(?:\.\d+)?(Z|[+-]\d\d:?\d\d)?$', text.strip())
    if not match:
        return None
    seconds = calendar.timegm(time.strptime(match.group(1), '%Y-%m-%dT%H:%M:%S'))
    zone = match.group(2)
    if zone and zone != 'Z':
        sign = 1 if zone[0] == '+' else -1
        hours, minutes = int(zone[1:3]), int(zone[-2:])
        seconds -= sign * (hours * 3600 + minutes * 60)
    return seconds


def branch_ahead(github, repo, branch):
    """How many commits a pushed branch has beyond main, besides its intent, and the files it changes."""
    quoted = urllib.request.quote(branch, safe='')
    status, body = github.get('/repos/%s/compare/main...%s' % (repo, quoted), BRANCH_TTL)
    if status != 200 or not isinstance(body, dict):
        return None, []
    files = [f.get('filename', '') for f in body.get('files') or [] if f.get('filename') != '.builder-intent']
    return body.get('ahead_by', 0), files


def waiting_need(state):
    tool = re.search(r'\(([^)]*)\)', state or '')
    tool = tool.group(1) if tool else ''
    if tool == 'AskUserQuestion':
        return 'Answer its question', 'It has stopped to ask you something. Open it and answer.'
    if tool == 'ExitPlanMode':
        return 'Approve its plan', 'It has a plan ready and is waiting for your go-ahead. Open it and approve or redirect it.'
    if tool:
        return 'Approve a step', 'It has paused to ask permission for a step. Open it and allow or deny it.'
    return 'Reply to it', 'It is paused waiting on you. Open it to see what it needs.'


def change_of(entry, github, progress, link, now):
    fix = entry['id']
    state = entry['state'] or ''
    summary = next((line.split(': ', 1)[-1] for line in (progress or '').splitlines() if line.startswith('Final summary')), '')
    head, card = report(summary)
    started = stamp_of(fix)
    last = utc_seconds(field(progress, 'Last activity') or '')
    landed_files = []
    for repo, sha in entry['commits'][:4]:
        landed_files += github.commit(repo, sha) or []
    branch_files, ahead = [], 0
    for repo, branch in entry['branches'][:4]:
        count, files = branch_ahead(github, repo, branch)
        ahead += count or 0
        branch_files += files
    if state.startswith('queued'):
        kind, label = 'queued', 'Starting'
    elif state.startswith('failed') or state.startswith('finished with an error'):
        kind, label = 'failed', 'Failed'
    elif state.startswith('waiting on input'):
        kind, label = 'waiting', 'Waiting on you'
    elif state in ('archived', 'dismissed on the board'):
        kind, label = 'closed', 'Closed'
    elif state.startswith('finished'):
        if entry['commits']:
            kind, label = 'landed', 'Landed'
        elif ahead:
            kind, label = 'ready', 'Ready, waiting to land'
        else:
            kind, label = 'done', 'Finished'
    else:
        kind, label = 'working', 'Working'
    repos = sorted({repo for repo, _ in entry['branches']} | {repo for repo, _ in entry['commits']})
    found = ['%s:%s' % (r, f) for r in repos for f in landed_files + branch_files]
    haystack = '\n'.join([entry['title'] or '', entry['brief'] or ''] + found + repos)
    areas = [name for name, pattern in AREA_PATTERNS if pattern.search(haystack)] or [DEFAULT_AREA]
    need = None
    if kind == 'waiting':
        action, detail = waiting_need(state)
        need = {'action': action, 'detail': detail}
    elif kind == 'ready':
        need = {'action': 'Approve landing', 'detail': 'It finished but did not land. Read its summary, then tell Butler to land it or say what to change.'}
    elif kind == 'landed' and card.get('Aaron must') and not NOTHING.match(card['Aaron must']):
        need = {'action': 'Do a hand step', 'detail': capital(plain(card['Aaron must']))}
    elif kind == 'failed':
        need = {'action': 'Decide what next', 'detail': 'It stopped with an error. Read what went wrong and ask Butler to retry or drop it.'}
    ended = last if kind in ('landed', 'ready', 'done', 'failed', 'closed') else None
    mentions = sorted(set(re.findall(r'\b[0-9]{8}-[0-9]{6}-[0-9]+\b', entry['brief'] or '')) - {fix})
    return {
        'id': fix,
        'title': clean(capital(plain(entry['title'])) or 'Untitled yet', 90),
        'purpose': purpose_of(entry['title'], entry['brief']),
        'kind': kind,
        'label': label,
        'started': started,
        'last': last,
        'ended': ended,
        'areas': areas,
        'need': {k: clean(v, 240) for k, v in need.items()} if need else None,
        'summary': clean(plain(sentences(head)[0] if sentences(head) else head), 240) or None,
        'changed': clean(plain(card.get('After') or card.get('Changed') or ''), 200) or None,
        'notice': clean(plain('; '.join(x for x in (card.get('Ready'), card.get('Go live')) if x)), 200) or None,
        'link': link,
        '_files': sorted(set(landed_files + branch_files)),
        '_mentions': mentions,
    }


def limits():
    usage = {}
    try:
        names = sorted(os.listdir(LIMITS_DIR))
    except OSError:
        names = []
    for name in names:
        match = re.fullmatch(r'claude-limits-([a-z0-9-]+)\.prom', name)
        if not match:
            continue
        account = match.group(1)
        entry = usage.setdefault(account, {'account': account, 'read': int(mtime(os.path.join(LIMITS_DIR, name)) or 0)})
        for line in (read(os.path.join(LIMITS_DIR, name)) or '').splitlines():
            metric = re.match(r'claude_limit_(percent|resets_at_seconds)\{[^}]*kind="(session|weekly_all)"[^}]*\}\s+([0-9.eE+-]+)$', line)
            if metric:
                key = metric.group(2).replace('weekly_all', 'weekly') + ('' if metric.group(1) == 'percent' else '_resets')
                value = float(metric.group(3))
                entry[key] = round(value) if metric.group(1) == 'percent' else int(value)
    return [usage[a] for a in sorted(usage, key=lambda a: (a != 'personal', a))]


def overlaps(changes):
    """Pairs of changes that share files, name each other, or touch the same part of the setup while both are live."""
    live = ('queued', 'working', 'waiting', 'ready')
    edges = []
    for i, a in enumerate(changes):
        for b in changes[i + 1:]:
            shared = sorted(set(a['_files']) & set(b['_files']))
            if b['id'] in a['_mentions'] or a['id'] in b['_mentions']:
                later, earlier = (a, b) if b['id'] in a['_mentions'] else (b, a)
                edges.append({'from': later['id'], 'to': earlier['id'], 'kind': 'builds on', 'detail': '%s builds on %s' % (later['title'], earlier['title'])})
            if shared and (a['kind'] in live or b['kind'] in live):
                both = a['kind'] in live and b['kind'] in live
                edges.append({'from': a['id'], 'to': b['id'], 'kind': 'conflict' if both else 'same files',
                              'detail': '%s and %s change the same %s' % (a['title'], b['title'], 'file' if len(shared) == 1 else '%d files' % len(shared))})
    return edges[:40]


def work_snapshot(github, now):
    open_fixes, recent = fixes(github, now)
    changes = []
    for entry in open_fixes + recent:
        progress = read(os.path.join(SELF_FIX, 'progress', entry['id']))
        started = read(os.path.join(SELF_FIX, 'sessions', entry['id'])) or ''
        link = re.search(r'https://claude\.ai/code/session_[A-Za-z0-9]+', started)
        changes.append(change_of(entry, github, progress, link.group(0) if link else None, now))
    edges = overlaps(changes)
    order = {'waiting': 0, 'ready': 1, 'failed': 2, 'landed': 3}
    needs = sorted((c for c in changes if c['need'] and (c['kind'] != 'landed' or now - (c['ended'] or 0) < DAY)),
                   key=lambda c: (order.get(c['kind'], 9), c['started'] or 0))
    live = [c for c in changes if c['kind'] in ('queued', 'working', 'waiting', 'ready')]
    working = sorted((c for c in changes if c['kind'] == 'working'), key=lambda c: c['started'] or 0)
    ready = [c for c in changes if c['kind'] == 'ready']
    next_landing = None
    if ready:
        next_landing = {'id': ready[0]['id'], 'title': ready[0]['title'], 'when': 'once you approve it'}
    elif working:
        next_landing = {'id': working[0]['id'], 'title': working[0]['title'], 'when': 'it started first, so it is likely next'}
    for change in changes:
        del change['_files'], change['_mentions']
    return {
        'version': 1,
        'generated': int(now),
        'counts': {
            'running': sum(c['kind'] in ('queued', 'working') for c in changes),
            'waiting': len(needs),
            'landed_today': sum(c['kind'] == 'landed' and now - (c['ended'] or 0) < DAY for c in changes),
            'live': len(live),
        },
        'next': next_landing,
        'needs': [{'id': c['id'], 'title': c['title'], 'action': c['need']['action'], 'detail': c['need']['detail'], 'link': c['link']} for c in needs],
        'changes': changes,
        'edges': edges,
        'usage': limits(),
    }


def work_main(argv):
    global STATE
    os.makedirs(os.path.join(WORK_DIR, 'cache'), mode=0o700, exist_ok=True)
    os.chmod(os.path.join(WORK_DIR, 'cache'), 0o700)
    STATE = os.path.join(WORK_DIR, 'cache')
    github = GitHub()
    snapshot = work_snapshot(github, time.time())
    github.save()
    target = os.path.join(WORK_DIR, 'work.json')
    with open(target + '.tmp', 'w') as f:
        json.dump(snapshot, f, ensure_ascii=False, separators=(',', ':'))
    os.chmod(target + '.tmp', 0o640)
    os.replace(target + '.tmp', target)
    print('butler-work: %d changes, %d need Aaron' % (len(snapshot['changes']), len(snapshot['needs'])))
    return 0


if __name__ == '__main__':
    sys.exit(work_main(sys.argv))
