"""Builds the "builders in flight" digest every change session reads.

It gathers, from spike's own records, each open change and each one that
ended in the last 48 hours: its id, title, state, the first paragraph of
its brief, the repositories and branches it touches, the files its branch
or landed commits change, read-only from GitHub's API, its `.builder-intent`,
and whether it waits on Aaron. It adds Aaron's own sessions on the kanban
board that work in the same repositories, and the `Notes from Butler`
section of butler-memory's skills/builders/SKILL.md.

The digest is written to the local file the change launcher appends to
each new brief, and committed to coordination/builders.md on the main of
kranners/butler-memory, only while GitHub confirms that repository is
private, and only when more than its refresh line changed.
"""
import base64
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request

SELF_FIX = '@selfFix@'
KANBAN = '@kanban@'
GIT = '@git@'
STATE = os.environ.get('STATE_DIRECTORY', '/var/lib/butler-builders')
GITHUB_TOKEN = '/var/lib/secrets/butler-github-issues-token'
MEMORY_REPO = 'kranners/butler-memory'
MEMORY_REMOTE = 'git@github.com:%s.git' % MEMORY_REPO
DIGEST_PATH = 'coordination/builders.md'
NOTES_PATH = 'skills/builders/SKILL.md'
AUTHOR = ('spike builders digest', 'butler-builders@spike.cute.engineer')

ID = re.compile(r'^[0-9]{8}-[0-9]{6}-[0-9]+$')
REPO = re.compile(r'(?:github\.com[/:])?([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+?)(?:\.git)?/?$')
KNOWN_REPOS = ('jimbo', 'claude-discord-threads', 'butler-memory', 'butler', 'kanban', 'backlogic')
ENDED = ('finished', 'archived', 'failed to start', 'dismissed')
WEEK = 7 * 24 * 3600
RECENT = 48 * 3600
BRANCH_TTL = 240
MAX_OPEN = 12
MAX_RECENT = 10
MAX_BOARD = 10
MAX_LINES = 200

# Anything shaped like a token or key, so none reaches the digest even if a brief quoted one.
SECRETS = re.compile(
    r'(gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9_-]{20,}'
    r'|xox[abposr]-[A-Za-z0-9-]{10,}|AKIA[0-9A-Z]{16}|eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_.-]+'
    r'|(?i:bearer)\s+[A-Za-z0-9._~+/=-]{16,}|\b[0-9a-fA-F]{48,}\b|-----BEGIN [A-Z ]+-----)'
)


def clean(text, limit):
    text = SECRETS.sub('[redacted]', re.sub(r'\s+', ' ', str(text or '')).strip())
    return text if len(text) <= limit else text[:limit - 1].rstrip() + '…'


def read(path):
    try:
        with open(path) as f:
            return f.read()
    except OSError:
        return None


def mtime(path):
    try:
        return os.stat(path).st_mtime
    except OSError:
        return None


def field(text, name):
    for line in (text or '').splitlines():
        if line.startswith(name + ': '):
            return line[len(name) + 2:]
    return None


def first_paragraph(brief):
    for paragraph in re.split(r'\n\s*\n', (brief or '').strip()):
        if paragraph.strip():
            return paragraph
    return ''


class GitHub:
    """Read-only GETs of GitHub's API, cached, with the token butler's github-issue already has."""

    def __init__(self):
        self.token = (read(GITHUB_TOKEN) or '').strip()
        self.cache_file = os.path.join(STATE, 'github-cache.json')
        try:
            self.cache = json.loads(read(self.cache_file) or '{}')
        except ValueError:
            self.cache = {}
        self.now = time.time()

    def get(self, path, ttl, auth=True):
        key = ('auth ' if auth else 'anon ') + path
        hit = self.cache.get(key)
        if hit and (ttl is None or self.now - hit['at'] < ttl):
            return hit['status'], hit['body']
        request = urllib.request.Request('https://api.github.com' + path, headers={
            'Accept': 'application/vnd.github+json',
            'User-Agent': 'butler-builders',
            'X-GitHub-Api-Version': '2022-11-28',
        })
        if auth and self.token:
            request.add_header('Authorization', 'Bearer ' + self.token)
        try:
            with urllib.request.urlopen(request, timeout=15) as response:
                status, body = response.status, json.loads(response.read() or b'null')
        except urllib.error.HTTPError as error:
            status, body = error.code, None
        except (urllib.error.URLError, OSError, ValueError):
            return None, None
        if isinstance(body, dict):
            # Only what the digest reads, so neither the cache nor memory holds patches or file contents it never shows.
            body = {
                'files': [{'filename': f.get('filename', '')} for f in body.get('files') or [] if isinstance(f, dict)],
                'ahead_by': body.get('ahead_by', 0),
                'private': body.get('private'),
                'encoding': body.get('encoding'),
                'content': (body.get('content') or '')[:4000] if '/contents/' in path else None,
            }
        if status in (200, 404):
            self.cache[key] = {'at': self.now, 'status': status, 'body': body}
        return status, body

    def save(self):
        fresh = {k: v for k, v in self.cache.items() if self.now - v['at'] < WEEK}
        with open(self.cache_file + '.tmp', 'w') as f:
            json.dump(fresh, f)
        os.replace(self.cache_file + '.tmp', self.cache_file)

    def memory_is_private(self):
        # Anonymously a private repository is a 404, and anyone who can see it is told whether it is private.
        status, body = self.get('/repos/' + MEMORY_REPO, 3600, auth=False)
        if status == 404 and self.token:
            status, body = self.get('/repos/' + MEMORY_REPO, 3600)
            if status == 404:
                return True
        if status == 404:
            return True
        if status == 200 and isinstance(body, dict):
            return body.get('private') is True
        return None

    def branch(self, repo, branch):
        """The files a pushed branch changes against main, and its .builder-intent."""
        quoted = urllib.request.quote(branch, safe='')
        status, body = self.get('/repos/%s/compare/main...%s' % (repo, quoted), BRANCH_TTL)
        if status == 404:
            return 'branch not pushed, so its files show once it lands', None
        if status != 200 or not isinstance(body, dict):
            return 'files unknown', None
        files = [f.get('filename', '') for f in body.get('files') or []]
        ahead = body.get('ahead_by', 0)
        status, intent = self.get('/repos/%s/contents/.builder-intent?ref=%s' % (repo, quoted), BRANCH_TTL)
        text = None
        if status == 200 and isinstance(intent, dict) and intent.get('encoding') == 'base64':
            try:
                text = base64.b64decode(intent.get('content', '')).decode('utf-8', 'replace')
            except ValueError:
                text = None
        files = [name for name in files if name != '.builder-intent']
        if not ahead:
            return 'nothing ahead of main', text
        return '%d commit%s ahead, files: %s' % (ahead, '' if ahead == 1 else 's', listing(files) if files else 'only its intent'), text

    def commit(self, repo, sha):
        status, body = self.get('/repos/%s/commits/%s' % (repo, sha), None)
        if status != 200 or not isinstance(body, dict):
            return None
        return [f.get('filename', '') for f in body.get('files') or []]


def listing(files, most=8):
    if not files:
        return 'none'
    shown = ', '.join(files[:most])
    return shown + (' and %d more' % (len(files) - most) if len(files) > most else '')


def repo_of(text):
    match = REPO.search(str(text or '').strip())
    if not match:
        name = str(text or '').strip()
        return 'kranners/' + name if name in KNOWN_REPOS else None
    return '%s/%s' % match.groups()


def landed_commits(summary):
    """The repository and short commit pairs on a landed fix's Commit: line."""
    match = re.search(r'Commit:\s*(.*)$', summary or '')
    if not match:
        return []
    found, repo = [], 'kranners/jimbo'
    for token in re.findall(r'[A-Za-z0-9_./-]+', match.group(1)):
        if '/' in token and REPO.fullmatch(token):
            repo = repo_of(token)
        elif token in KNOWN_REPOS:
            repo = 'kranners/' + token
        elif re.fullmatch(r'[0-9a-f]{7,40}', token):
            found.append((repo, token[:12]))
    return found


def fixes(github, now):
    ids = set()
    for directory in ('sessions', 'queue', 'briefs'):
        try:
            names = os.listdir(os.path.join(SELF_FIX, directory))
        except OSError:
            continue
        for name in names:
            fix = name[:-5] if name.endswith('.json') else name
            seen = mtime(os.path.join(SELF_FIX, directory, name))
            if ID.match(fix) and seen and now - seen < WEEK:
                ids.add(fix)
    open_fixes, recent = [], []
    for fix in sorted(ids):
        started = read(os.path.join(SELF_FIX, 'sessions', fix))
        progress = read(os.path.join(SELF_FIX, 'progress', fix))
        queued = read(os.path.join(SELF_FIX, 'queue', fix + '.json'))
        brief = read(os.path.join(SELF_FIX, 'briefs', fix))
        if brief is None and queued:
            try:
                brief = json.loads(queued).get('request')
            except ValueError:
                brief = None
        if started is None:
            state = 'queued, starting within a minute'
        elif not started.startswith('Started '):
            state = 'failed to start'
        else:
            state = field(progress, 'State') or 'started, progress not read yet'
        if os.path.exists(os.path.join(SELF_FIX, 'archived', fix)):
            state = 'archived'
        elif os.path.exists(os.path.join(SELF_FIX, 'dismissed', fix)):
            state = 'dismissed on the board'
        ended = state.startswith(ENDED)
        last = max(filter(None, [mtime(os.path.join(SELF_FIX, d, fix)) for d in ('progress', 'sessions', 'archived', 'dismissed')]), default=None)
        if ended and (last is None or now - last > RECENT):
            continue
        summary = next((line.split(': ', 1)[-1] for line in (progress or '').splitlines() if line.startswith('Final summary')), '')
        entry = {
            'id': fix,
            'title': field(progress, 'Title'),
            'state': state,
            'waiting': state.startswith('waiting on input'),
            'brief': first_paragraph(brief) if brief else None,
            'branches': [],
            'commits': [],
        }
        for line in (progress or '').splitlines():
            if line.startswith('Branch: '):
                parts = line[len('Branch: '):].split(' ', 1)
                repo = repo_of(parts[0])
                for branch in (parts[1] if len(parts) > 1 else '').split(', '):
                    if repo and branch.strip():
                        entry['branches'].append((repo, branch.strip()))
        entry['commits'] = landed_commits(summary)
        (recent if ended else open_fixes).append(entry)
    return open_fixes[-MAX_OPEN:][::-1], recent[-MAX_RECENT:][::-1]


def describe(entry, github):
    title = clean(entry['title'] or 'untitled yet', 100)
    lines = ['### %s: %s' % (entry['id'], title)]
    lines.append('- State: %s; waits on Aaron: %s' % (clean(entry['state'], 120), 'yes' if entry['waiting'] else 'no'))
    stamp = time.strptime(entry['id'][:15], '%Y%m%d-%H%M%S')
    lines.append('- Asked: %s' % time.strftime('%a %-d %b %H:%M', stamp))
    lines.append('- Brief: %s' % (clean(entry['brief'], 500) if entry['brief'] else 'not kept (started before briefs were kept)'))
    intents = []
    repos = sorted({repo for repo, _ in entry['branches']} | {repo for repo, _ in entry['commits']})
    for repo, branch in entry['branches'][:4]:
        files, intent = github.branch(repo, branch)
        lines.append('- Branch %s %s: %s' % (repo, clean(branch, 80), clean(files, 400)))
        if intent:
            intents.append(clean(intent, 300))
    for intent in intents[:2]:
        lines.append('- Intent: %s' % intent)
    if entry['commits']:
        landed = []
        for repo, sha in entry['commits'][:4]:
            files = github.commit(repo, sha)
            landed.append('%s %s (%s)' % (repo, sha, listing(files, 6) if files is not None else 'files unknown'))
        lines.append('- Landed: %s' % clean('; '.join(landed), 500))
    if not repos and not entry['branches']:
        lines.append('- Repos: not known yet')
    return lines, repos


def board_sessions(repos):
    """Aaron's working sessions on the board in the same repositories, as work-in-progress notes."""
    try:
        result = subprocess.run([KANBAN, 'board_snapshot'], input='', capture_output=True, text=True, timeout=60)
    except subprocess.TimeoutExpired:
        return ['- Could not read the board: it did not answer in time.']
    if result.returncode != 0:
        return ['- Could not read the board: %s' % clean(result.stderr or 'pilot unreachable', 160)]
    names = {repo.split('/')[-1] for repo in repos} | set(KNOWN_REPOS)

    def repo_in(cwd):
        parts = [p for p in re.split(r'/\.claude/worktrees/|/', str(cwd or '')) if p]
        for part in reversed(parts):
            base = part.split('--')[0]
            if base in names:
                return base
        return None

    # The snapshot is a JSON object, which the board may follow with lines of its own.
    start = result.stdout.find('{')
    try:
        snapshot = json.JSONDecoder().raw_decode(result.stdout[start:])[0] if start >= 0 else None
    except ValueError:
        snapshot = None
    sessions = []
    if isinstance(snapshot, dict):
        sessions = snapshot.get('sessions') or snapshot.get('cards') or []
    elif isinstance(snapshot, list):
        sessions = snapshot
    lines = []
    if sessions:
        for session in sessions:
            if not isinstance(session, dict):
                continue
            state = str(session.get('state') or session.get('activity') or session.get('status') or '')
            if state.lower() in ('', 'idle', 'done', 'finished', 'ended', 'exited', 'stopped', 'closed', 'failed'):
                continue
            cwd = session.get('cwd') or session.get('dir') or session.get('path')
            repo = repo_in(cwd)
            if not repo:
                continue
            summary = next((session[key] for key in ('summary', 'latestSummary', 'doing', 'status', 'title') if isinstance(session.get(key), str) and session[key]), '')
            lines.append('- %s (%s) in %s: WIP note, not a decision: %s' % (
                clean(session.get('name') or session.get('short') or session.get('id'), 80),
                clean(state, 20), clean(cwd, 120), clean(summary, 300)))
    elif snapshot is None and result.stdout.strip():
        # Not JSON: keep the lines that name one of the repositories.
        for line in result.stdout.splitlines():
            if any(re.search(r'\b%s\b' % re.escape(name), line) for name in names):
                lines.append('- WIP note, not a decision: %s' % clean(line, 300))
    return lines[:MAX_BOARD] or ['- None working in these repositories right now.']


def notes(memory):
    text = read(os.path.join(memory, NOTES_PATH))
    if not text:
        return ['_No notes yet: Butler keeps them in butler-memory\'s skills/builders/SKILL.md under a `Notes from Butler` heading._']
    text = re.sub(r'\A---\n.*?\n---\n', '', text, flags=re.S)
    lines = text.splitlines()
    start = next((i for i, line in enumerate(lines) if re.match(r'#+\s*Notes from Butler', line, re.I)), None)
    if start is not None:
        level = len(lines[start]) - len(lines[start].lstrip('#'))
        body = []
        for line in lines[start + 1:]:
            if re.match(r'#{1,%d}\s' % level, line):
                break
            body.append(line)
        lines = body
    lines = [SECRETS.sub('[redacted]', line)[:300] for line in lines]
    while lines and not lines[0].strip():
        lines.pop(0)
    while lines and not lines[-1].strip():
        lines.pop()
    return lines[:40] or ['_No notes yet._']


def build(memory, github):
    now = time.time()
    open_fixes, recent = fixes(github, now)
    out = [
        '# Builders in flight',
        '',
        'Generated by spike from butler\'s change records, GitHub and Aaron\'s kanban board; private, kept only in kranners/butler-memory.',
        'Read it when you start and again right before you push or land. Where you touch a file or a shared design (access, auth, the iPad peer, kanban transport, approvals) an earlier change also touches, rebase on its work, reconcile with it and say so in your summary.',
        '',
        '## Notes from Butler',
        '',
    ]
    out += notes(memory)
    repos = set()
    out += ['', '## Open changes', '']
    if not open_fixes:
        out.append('None.')
    for entry in open_fixes:
        lines, touched = describe(entry, github)
        repos |= set(touched)
        out += lines + ['']
    out += ['## Landed or closed in the last 48 hours', '']
    if not recent:
        out.append('None.')
    for entry in recent:
        lines, touched = describe(entry, github)
        repos |= set(touched)
        out += lines + ['']
    out += ['## Aaron\'s own board sessions in these repositories', '']
    out += board_sessions(repos)
    if len(out) > MAX_LINES - 2:
        out = out[:MAX_LINES - 2] + ['', '_Cut off at %d lines._' % MAX_LINES]
    return '\n'.join(out).rstrip() + '\n'


def git(memory, *args, check=True):
    return subprocess.run([GIT, '-C', memory, *args], capture_output=True, text=True, check=check, timeout=120)


def sync_memory(memory):
    if not os.path.isdir(os.path.join(memory, '.git')):
        subprocess.run([GIT, 'clone', '--quiet', '--depth', '1', '--branch', 'main', MEMORY_REMOTE, memory],
                       capture_output=True, text=True, check=True, timeout=300)
    git(memory, 'fetch', '--quiet', '--depth', '1', 'origin', 'main')
    git(memory, 'reset', '--quiet', '--hard', 'FETCH_HEAD')


def publish(memory, body, stamp):
    """Commits the digest to butler-memory's main, unless only its refresh line would change."""
    path = os.path.join(memory, DIGEST_PATH)
    old = read(path)
    if old is not None and re.sub(r'\ARefreshed: .*\n\n', '', old) == body:
        return 'unchanged'
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w') as f:
        f.write('Refreshed: %s\n\n' % stamp + body)
    git(memory, 'add', DIGEST_PATH)
    git(memory, '-c', 'user.name=%s' % AUTHOR[0], '-c', 'user.email=%s' % AUTHOR[1],
        'commit', '--quiet', '--message', 'Refresh the builders in flight digest')
    pushed = git(memory, 'push', '--quiet', 'origin', 'HEAD:main', check=False)
    return 'pushed' if pushed.returncode == 0 else 'rejected'


def main(argv):
    memory = os.path.join(STATE, 'memory')
    github = GitHub()
    stamp = time.strftime('%a %-d %b %Y %H:%M %Z')
    private = github.memory_is_private()
    try:
        sync_memory(memory)
        synced = True
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
        print('butler-builders: could not fetch butler-memory: %s' % clean(getattr(error, 'stderr', '') or error, 300), file=sys.stderr)
        synced = False
    body = build(memory, github)
    with open(os.path.join(STATE, 'builders.md.tmp'), 'w') as f:
        f.write('Refreshed: %s\n\n' % stamp + body)
    os.replace(os.path.join(STATE, 'builders.md.tmp'), os.path.join(STATE, 'builders.md'))
    github.save()
    if not synced:
        return 1
    if private is not True:
        print('butler-builders: not publishing, GitHub did not confirm %s is private' % MEMORY_REPO, file=sys.stderr)
        return 0
    for _ in range(3):
        outcome = publish(memory, body, stamp)
        if outcome != 'rejected':
            print('butler-builders: digest %s, %d lines' % (outcome, body.count('\n')))
            return 0
        sync_memory(memory)
    print('butler-builders: could not push the digest; the next run tries again', file=sys.stderr)
    return 1


if __name__ == '__main__':
    sys.exit(main(sys.argv))
