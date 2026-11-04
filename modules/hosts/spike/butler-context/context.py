"""Butler's context packs: the same compact picture of each area of Aaron's life on every surface.

`butler-context generate`, run by root every few minutes, builds one plain
text pack per area from Butler's memory (core, skills, the journal), the
builders in flight digest, the kanban board's snapshot and, for Bloom
work, read-only facts about the repositories on pilot: paths, branches,
latest commit subjects, open pull requests, README titles and the skynet
index's file names. It writes them, and an index of them, to a directory
butler reads but cannot write.

Every line passes a filter that drops anything shaped like a secret,
money, health, mail or a contact detail, so a pack holds pointers and one
line summaries, never message bodies or private figures, and no Bloom
code or document leaves pilot beyond its name.

Butler reads them with `context list`, `context show <area>` and
`context refresh <area>`; `context prefix`, given {"cwd", "text"} on
stdin, prints the block that kanban's start_session and send_prompt and
the change launcher put in front of what they send.
"""
import json
import os
import re
import subprocess
import sys
import time

PACKS = os.environ.get('BUTLER_CONTEXT_DIR', '@packs@')
REFRESH = os.environ.get('BUTLER_CONTEXT_REFRESH', '@refresh@')
MEMORY = os.environ.get('BUTLER_CONTEXT_MEMORY', '@memory@')
DIGEST = os.environ.get('BUTLER_CONTEXT_DIGEST', '@digest@')
KANBAN = os.environ.get('BUTLER_CONTEXT_KANBAN', '@kanban@')
SSH = os.environ.get('BUTLER_CONTEXT_SSH', '@ssh@')
PILOT = json.loads(os.environ.get('BUTLER_CONTEXT_PILOT') or '@pilot@')
GROUP = os.environ.get('BUTLER_CONTEXT_GROUP', '@group@')
TZ = '@timeZone@'

PACK_LIMIT = 6000
PREFIX_LIMIT = 3500
REFRESH_WAIT = 45
JOURNAL_DAYS = 3

AREAS = {
    'board': {
        'title': "Aaron's kanban board and his Claude Code sessions on pilot",
        'words': ['kanban', 'board', 'sessions?', 'pilot', 'cards?', 'regions?', 'popup', 'runners?', 'worktrees?'],
        'pointers': [
            'The board runs on pilot at http://127.0.0.1:7420/ and Butler reaches it with `kanban`; spike keeps a card per change.',
            "Sessions are Aaron's cards: Butler starts, prompts and finishes them only with his approval.",
        ],
    },
    'bloom': {
        'title': 'Bloom work: skynet and the HKJC and tennis repositories on pilot',
        'words': ['bloom', 'skynet', 'hkjc', 'tennis', 'omnidash', 'racemate', 'takeormake', 'odds', 'scores', 'racing', 'capture'],
        'pointers': [
            "Bloom is Aaron's employer; its code and documents stay on pilot, so this pack holds only paths, names and one line summaries.",
            'Read the detail on pilot, read-only, with `mac pilot run`; skynet, Bloom\'s knowledge base, is ~/repos/skynet-memory there (skill `skynet`).',
        ],
    },
    'home': {
        'title': "Aaron's home setup and framer, the kitchen panel",
        'words': ['home', 'home assistant', 'framer', 'panel', 'kitchen', 'lights?', 'zones?', 'vacuum', 'wake word', 'screensaver', 'spike', 'jimbo', 'piggys-mbp', 'keep-awake', 'wireguard', 'ipad', 'phones?', 'satellite'],
        'pointers': [
            'Home Assistant runs on spike (`home` reads and drives its devices); framer is the Surface Book kiosk on the kitchen wall showing its panel and hearing "hey butler".',
            "spike is the always-on home server; piggys-MBP is Aaron's personal Mac, pilot his work Mac, jimbo his PC (skill `machines`).",
        ],
    },
    'butler': {
        'title': "Butler's own systems",
        'words': ['butler', 'changes?', 'self-fix', 'daemon', 'discord', 'memory', 'voice', 'calls?', 'realtime', 'mood', 'approvals?', 'grants?', 'landing', 'land', 'monitor', 'skills?', 'cron', 'jobs?', 'threads?', 'persona', 'kokoro', 'lewis', 'probe', 'builders'],
        'pointers': [
            "Butler is the claude-discord-threads daemon on spike, configured by jimbo's modules/hosts/spike/butler*.nix, with memory in kranners/butler-memory and the life index in kranners/butler.",
            'A change to Butler is made with `change start` and lands on main; `change list` shows those in flight.',
        ],
    },
    'personal': {
        'title': "Aaron's personal life items: plans, errands, trips and events",
        'words': ['calendar', 'reminders?', 'trip', 'tokyo', 'film', 'movie', 'christmas', 'licence', 'idp', 'tickets?', 'apartment', 'garden', 'decorat\\w*', 'errands?', 'amazon', 'buy', 'parkhouse', 'birthday', 'dinner', 'holiday', 'concert', 'gig', 'rylee', 'goals?'],
        'pointers': [
            'Plans and errands live in the calendar (`calendar`) and reminders (`reminders`); health, money and mail stay in their own tools and never in this pack.',
        ],
    },
}

# Repositories that belong to an area, by a name in a session's working directory.
REPO_AREAS = {
    'kanban': 'board',
    'jimbo': 'butler',
    'claude-discord-threads': 'butler',
    'butler-memory': 'butler',
    'butler': 'butler',
}

# Butler's own memory files that are health plans or inferred from his payments and messages, never read for a pack.
SKIPPED_CORE = {'training.md', 'workout-plan.md', 'inferred.md'}

SECRETS = re.compile(
    r'(gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9_-]{20,}'
    r'|xox[abposr]-[A-Za-z0-9-]{10,}|AKIA[0-9A-Z]{16}|eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_.-]+'
    r'|(?i:bearer)\s+[A-Za-z0-9._~+/=-]{16,}|\b[0-9a-fA-F]{40,}\b|-----BEGIN [A-Z ]+-----)'
)

# A line carrying any of these is dropped whole: money, health, mail, contact details and credentials.
PRIVATE = re.compile(
    r'(\$\s?\d|\d\s?(?:aud|usd|dollars?)\b'
    r'|\b(?:salary|debts?|loans?|bank(?:ing)?|balances?|payments?|payoff|runway|savings?|invoices?|charged?|refunds?|spend(?:ing)?'
    r'|transactions?|transfers?|mastercard|visa|card ending|billing|budget|afford\w*|financ\w*|income|purchases?|\(up\)|up bank|up transfers?'
    r'|westpac|citibank|hostplus|spaceship|cmc|up bank|super(?:annuation)?|help balance|tax(?:es)?|mortgage|rent|bond'
    r'|health|sleep|hrv|heart|kg|lifts?|lifting|gym|reps|squats?|deadlifts?|leg extension|calories|diet|body battery|stress|weight|workouts?|training|injur\w*|doctor|gp|medic\w*|symptoms?|garmin|hevy'
    r'|e-?mails?|mail|inbox|e-ticket|messenger|slack|dms?|text messages?|imessage|sms'
    r'|passwords?|passcodes?|tokens?|secrets?|api keys?|credentials?|2fa|pin|keys? on spike)\b'
    r'|[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'
    r'|(?<![\w-])\+?\(?\d{2,4}\)?[ -]?\d{3,4}[ -]?\d{3,4}(?![\w-])'
    r'|-?\d{1,3}\.\d{4,})',
    re.IGNORECASE,
)


def clean(text, limit):
    text = SECRETS.sub('[redacted]', re.sub(r'\s+', ' ', str(text or '')).strip())
    return text if len(text) <= limit else text[:limit - 1].rstrip() + '…'


def safe(text):
    return not PRIVATE.search(text or '') and not SECRETS.search(text or '')


def matcher(words):
    return re.compile(r'\b(%s)\b' % '|'.join(words), re.IGNORECASE)


MATCHERS = {name: matcher(area['words']) for name, area in AREAS.items()}


def read(path):
    try:
        with open(path, errors='replace') as f:
            return f.read()
    except OSError:
        return None


def stamp(when=None):
    os.environ['TZ'] = TZ
    time.tzset()
    return time.strftime('%a %-d %b %H:%M', time.localtime(when))


# Sources.

def memory_lines(name):
    """Lines of Butler's core memory and recent journal about an area, private ones dropped."""
    found = MATCHERS[name]
    core, journal = [], []
    directory = os.path.join(MEMORY, 'core')
    try:
        files = sorted(f for f in os.listdir(directory) if f.endswith('.md') and f not in SKIPPED_CORE)
    except OSError:
        files = []
    for file in files:
        for line in (read(os.path.join(directory, file)) or '').splitlines():
            line = line.strip()
            if not line or line.startswith('#') or line.startswith('---'):
                continue
            line = re.sub(r'^[-*]\s+', '', line)
            if found.search(line) and safe(line):
                core.append('%s (core/%s)' % (clean(line, 220), file))
    directory = os.path.join(MEMORY, 'journal')
    try:
        days = sorted((f for f in os.listdir(directory) if re.match(r'^\d{4}-\d{2}-\d{2}\.md$', f)), reverse=True)[:JOURNAL_DAYS]
    except OSError:
        days = []
    for day in days:
        text = read(os.path.join(directory, day)) or ''
        heading = ''
        for paragraph in re.split(r'\n\s*\n', text):
            paragraph = paragraph.strip()
            if paragraph.startswith('## '):
                heading, _, paragraph = paragraph.partition('\n')
                heading = heading[3:].strip()
                paragraph = paragraph.strip()
            if not paragraph:
                continue
            first = re.split(r'(?<=[.!?])\s', re.sub(r'\s+', ' ', paragraph), maxsplit=1)[0]
            if found.search(paragraph) and safe(first):
                journal.append('%s %s: %s' % (day[:-3], heading, clean(first, 200)))
    return core[:14], journal[:10]


def memory_skills(name):
    found = MATCHERS[name]
    skills = []
    directory = os.path.join(MEMORY, 'skills')
    try:
        names = sorted(os.listdir(directory))
    except OSError:
        names = []
    for skill in names:
        text = read(os.path.join(directory, skill, 'SKILL.md')) or ''
        match = re.search(r'^description:\s*(.+)$', text, re.MULTILINE)
        description = match.group(1).strip() if match else ''
        sentence = re.split(r'(?<=[.!?])\s', description, maxsplit=1)[0]
        if (found.search(skill) or found.search(description)) and safe(skill + ' ' + sentence):
            skills.append('`%s`: %s' % (skill, clean(sentence, 140)))
    return skills[:8]


def digest_changes():
    """The open and recently ended changes from the builders in flight digest, as id, title and state."""
    text = read(DIGEST) or ''
    changes = []
    section = None
    current = None
    for line in text.splitlines():
        if line.startswith('## '):
            section = 'open' if line.startswith('## Open changes') else 'recent' if line.startswith('## Landed or closed') else None
            continue
        if section is None:
            continue
        heading = re.match(r'^### ([0-9]{8}-[0-9]{6}-[0-9]+): (.*)$', line)
        if heading:
            current = {'id': heading.group(1), 'title': clean(heading.group(2), 120), 'state': '', 'open': section == 'open', 'brief': ''}
            changes.append(current)
        elif current and line.startswith('- State: '):
            current['state'] = clean(line[len('- State: '):].split(';')[0], 60)
        elif current and line.startswith('- Brief: '):
            current['brief'] = line[len('- Brief: '):]
    return changes


def board_snapshot():
    try:
        result = subprocess.run([KANBAN, 'board_snapshot'], input='', capture_output=True, text=True, timeout=100)
    except (subprocess.TimeoutExpired, OSError) as error:
        return None, 'the board did not answer: %s' % error
    if result.returncode != 0:
        return None, clean(result.stderr or 'pilot unreachable', 160)
    start = result.stdout.find('{')
    try:
        snapshot = json.JSONDecoder().raw_decode(result.stdout[start:])[0] if start >= 0 else None
    except ValueError:
        snapshot = None
    if not isinstance(snapshot, dict):
        return None, 'the board answered with something other than a snapshot'
    sessions = []
    for session in snapshot.get('sessions') or snapshot.get('cards') or []:
        if not isinstance(session, dict):
            continue
        sessions.append({
            'id': clean(session.get('short') or session.get('id'), 40),
            'fullId': clean(session.get('id'), 80),
            'name': clean(session.get('name') or session.get('title') or session.get('short') or session.get('id'), 80),
            'state': clean(session.get('state') or session.get('activity') or session.get('status'), 20),
            'cwd': clean(session.get('cwd') or session.get('dir') or session.get('path'), 140),
            'summary': clean(next((session[key] for key in ('summary', 'latestSummary', 'doing', 'status', 'title') if isinstance(session.get(key), str) and session[key]), ''), 160),
        })
    regions = [clean(region.get('name') or region.get('title') or region.get('label'), 60)
               for region in snapshot.get('regions') or [] if isinstance(region, dict)]
    return {'sessions': sessions, 'regions': [r for r in regions if r]}, None


# A fixed read-only script, run on pilot as Aaron: git reads, `gh pr list` and directory listings, nothing else.
PILOT_SCRIPT = r'''
export GH_PROMPT_DISABLED=1 GIT_OPTIONAL_LOCKS=0 PATH="/opt/homebrew/bin:/etc/profiles/per-user/$USER/bin:/run/current-system/sw/bin:$PATH"
for d in "$HOME"/* "$HOME"/workspace/* "$HOME"/repos/*; do
  [ -d "$d/.git" ] || [ -f "$d/.git" ] || continue
  name=$(basename "$d")
  case "$(printf %s "$name" | tr A-Z a-z)" in
    *bloom*|*hkjc*|*tennis*|*skynet*|*omnidash*|*racemate*|*takeormake*) ;;
    *) continue ;;
  esac
  path=${d/#$HOME/\~}
  printf 'repo\t%s\t%s\t%s\t%s\n' "$path" "$(git -C "$d" symbolic-ref --short -q HEAD || echo detached)" \
    "$(git -C "$d" log -1 --format=%cr 2>/dev/null)" "$(git -C "$d" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
  git -C "$d" log -3 --no-merges --format="commit%x09$path%x09%s" 2>/dev/null
  for r in README.md readme.md README; do
    [ -f "$d/$r" ] && { printf 'readme\t%s\t%s\t%s\n' "$path" "$r" "$(grep -m1 '^#' "$d/$r" | sed 's/^#* *//')"; break; }
  done
  if command -v gh >/dev/null 2>&1 && git -C "$d" remote get-url origin 2>/dev/null | grep -q github.com; then
    (cd "$d" && gh pr list --author @me --state open --limit 5 --json number,title,headRefName,isDraft \
      --template '{{range .}}{{printf "pr\t'"$path"'\t#%v %s (%s)\n" .number .title .headRefName}}{{end}}' 2>/dev/null) &
    pid=$!; ( sleep 8; kill $pid 2>/dev/null ) >/dev/null 2>&1 & wait $pid 2>/dev/null
  fi
done
s="$HOME/repos/skynet-memory"
if [ -d "$s" ]; then
  for f in "$s"/core/* "$s"/skills/*; do [ -e "$f" ] && printf 'skynet\t%s\n' "${f#$s/}"; done
fi
'''


def pilot_facts():
    key = os.path.join(os.environ.get('CREDENTIALS_DIRECTORY', ''), 'butler-mac-key')
    options = ['-i', key, '-o', 'IdentitiesOnly=yes', '-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=accept-new', '-o', 'ConnectTimeout=5']
    known = os.environ.get('KANBAN_KNOWN_HOSTS')
    if known:
        options += ['-o', 'UserKnownHostsFile=' + known]
    try:
        result = subprocess.run([SSH, *options, '%s@%s' % (PILOT['user'], PILOT['address']), 'bash -s'],
                                input=PILOT_SCRIPT, capture_output=True, text=True, timeout=90)
    except (subprocess.TimeoutExpired, OSError) as error:
        return None, 'pilot did not answer: %s' % error
    if result.returncode == 255:
        return None, 'pilot is unreachable over ssh'
    repos, skynet = {}, []
    for line in result.stdout.splitlines():
        parts = line.split('\t')
        if parts[0] == 'repo' and len(parts) >= 5:
            repos[parts[1]] = {'path': parts[1], 'branch': clean(parts[2], 60), 'last': clean(parts[3], 40), 'dirty': parts[4], 'commits': [], 'prs': [], 'readme': None}
        elif parts[0] == 'commit' and len(parts) >= 3 and parts[1] in repos:
            repos[parts[1]]['commits'].append(clean(parts[2], 90))
        elif parts[0] == 'pr' and len(parts) >= 3 and parts[1] in repos:
            repos[parts[1]]['prs'].append(clean(parts[2], 110))
        elif parts[0] == 'readme' and len(parts) >= 4 and parts[1] in repos:
            repos[parts[1]]['readme'] = '%s "%s"' % (parts[2], clean(parts[3], 80))
        elif parts[0] == 'skynet' and len(parts) >= 2:
            skynet.append(clean(parts[1], 60))
    return {'repos': list(repos.values())[:16], 'skynet': skynet[:60]}, None


def cached(name, fetch):
    """A source's latest answer, or its last good one with when it was read, while it cannot be reached."""
    path = os.path.join(PACKS, '.cache-%s.json' % name)
    value, error = fetch()
    if value is not None:
        write(path, json.dumps({'at': time.time(), 'value': value}))
        return value, None
    try:
        old = json.loads(read(path) or '')
        return old['value'], '%s; showing what was read %s' % (error, stamp(old['at']))
    except (ValueError, KeyError, TypeError):
        return None, error


# Areas and packs.

def area_of_path(cwd):
    parts = [p for p in re.split(r'/\.claude/worktrees/|/', str(cwd or '')) if p]
    for part in reversed(parts):
        lower = part.lower()
        if any(word in lower for word in ('bloom', 'hkjc', 'tennis', 'skynet', 'omnidash', 'racemate', 'takeormake')):
            return 'bloom'
        base = lower.split('--')[0]
        if base in REPO_AREAS:
            return REPO_AREAS[base]
    return None


def area_for(cwd, text):
    """The area a session's folder belongs to, else the one its text names most."""
    by_path = area_of_path(cwd)
    if by_path:
        return by_path
    scores = {name: len(found.findall(text or '')) for name, found in MATCHERS.items()}
    best = max(scores, key=lambda name: scores[name])
    return best if scores[best] else None


def session_line(session):
    return '- %s [%s]%s%s' % (
        session['name'], session['state'] or 'unknown',
        ' in %s' % session['cwd'] if session['cwd'] else '',
        ': %s' % session['summary'] if session['summary'] and session['summary'] != session['name'] else '')


def build_pack(name, board, board_error, pilot, pilot_error, changes, now):
    area = AREAS[name]
    found = MATCHERS[name]
    lines = ['# Context pack: %s' % name, '', area['title'] + '.',
             'Refreshed %s by spike from Butler\'s memory, the builders digest, the kanban board%s.' % (stamp(now), ' and read-only facts from pilot' if name == 'bloom' else ''),
             'Pointers and one line summaries only; check the source before relying on a detail.', '']
    lines += ['## Pointers'] + ['- ' + p for p in area['pointers']] + ['']

    if board is not None or board_error:
        sessions = board['sessions'] if board else []
        live = [s for s in sessions if s['state'].lower() not in ('done', 'finished', 'ended', 'exited', 'stopped', 'closed')]
        if name == 'board':
            mine = live
        else:
            mine = [s for s in live if area_of_path(s['cwd']) == name or (not area_of_path(s['cwd']) and found.search(s['name'] + ' ' + s['summary']))]
        if mine or board_error or name in ('board', 'bloom'):
            lines.append('## Sessions on the board')
            if board_error:
                lines.append('- (%s)' % board_error)
            lines += [session_line(s) for s in mine[:20]] or ['- None open in this area.']
            if name == 'board' and board and board['regions']:
                lines.append('- Regions: ' + ', '.join(board['regions'][:12]))
            lines.append('')

    if name == 'bloom':
        lines.append('## Repositories on pilot')
        if pilot_error:
            lines.append('- (%s)' % pilot_error)
        for repo in (pilot or {}).get('repos', []):
            dirty = ', %s uncommitted files' % repo['dirty'] if repo['dirty'] not in ('', '0') else ''
            lines.append('- %s: on %s, last commit %s%s' % (repo['path'], repo['branch'], repo['last'] or 'unknown', dirty))
            if repo['commits']:
                lines.append('  latest: ' + '; '.join(repo['commits']))
            if repo['prs']:
                lines.append('  open PRs: ' + '; '.join(repo['prs']))
            if repo['readme']:
                lines.append('  read first: ' + repo['readme'])
        if pilot and pilot.get('skynet'):
            lines.append('- skynet index (~/repos/skynet-memory): ' + ', '.join(pilot['skynet']))
        lines.append('')

    relevant = [c for c in changes if name == 'butler' or found.search(c['title'] + ' ' + c['brief'])]
    open_changes = [c for c in relevant if c['open']]
    recent = [c for c in relevant if not c['open']]
    if open_changes or recent:
        lines.append('## Changes in flight')
        lines += ['- %s %s [%s]' % (c['id'], c['title'], c['state']) for c in open_changes[:8]]
        if recent:
            lines.append('- Ended in the last 2 days: ' + '; '.join('%s %s' % (c['id'], c['title']) for c in recent[:6]))
        lines.append('')

    core, journal = memory_lines(name)
    if core:
        lines += ['## From memory'] + ['- ' + line for line in core] + ['']
    if journal:
        lines += ['## Lately (journal)'] + ['- ' + line for line in journal] + ['']
    skills = memory_skills(name)
    if skills:
        lines += ['## Skills to load'] + ['- ' + s for s in skills] + ['']

    text = '\n'.join(SECRETS.sub('[redacted]', line) for line in lines).strip() + '\n'
    if len(text) > PACK_LIMIT:
        text = text[:PACK_LIMIT].rsplit('\n', 1)[0] + '\n(cut off at %d characters)\n' % PACK_LIMIT
    return text


def write(path, text):
    temp = path + '.tmp'
    with open(temp, 'w') as f:
        f.write(text)
    os.chmod(temp, 0o640)
    if GROUP and os.geteuid() == 0:
        import grp
        try:
            os.chown(temp, 0, grp.getgrnam(GROUP).gr_gid)
        except KeyError:
            pass
    os.rename(temp, path)


def index_text(now, sizes):
    lines = [
        '# Context packs',
        '',
        'Spike keeps one context pack per area of Aaron\'s life, refreshed every 5 minutes (last %s), so every surface, Discord, the board\'s popup, calls and the kitchen panel, works from the same picture.' % stamp(now),
        'Before answering about an area, or briefing a session or change on it, read its pack with `context show <area>`; `context refresh <area>` rebuilds it first.',
        'kanban\'s start_session and send_prompt, and `change start`, put the matching pack in front of what they send by themselves; say which pack a session received.',
        '',
    ]
    for name, area in AREAS.items():
        lines.append('- `%s`: %s (%d lines)' % (name, area['title'], sizes.get(name, 0)))
    return '\n'.join(lines) + '\n'


def generate():
    now = time.time()
    os.makedirs(PACKS, exist_ok=True)
    board, board_error = cached('board', board_snapshot)
    pilot, pilot_error = cached('pilot', pilot_facts)
    changes = digest_changes()
    sizes = {}
    for name in AREAS:
        text = build_pack(name, board, board_error, pilot, pilot_error, changes, now)
        write(os.path.join(PACKS, name + '.md'), text)
        sizes[name] = text.count('\n')
    write(os.path.join(PACKS, 'index.md'), index_text(now, sizes))
    try:
        for request in os.listdir(REFRESH):
            os.remove(os.path.join(REFRESH, request))
    except OSError:
        pass
    print('butler-context: wrote %s' % ', '.join('%s (%d lines)' % item for item in sizes.items()))
    if board_error:
        print('butler-context: board: %s' % board_error, file=sys.stderr)
    if pilot_error:
        print('butler-context: pilot: %s' % pilot_error, file=sys.stderr)
    return 0


# Butler's command.

def show(name):
    text = read(os.path.join(PACKS, name + '.md'))
    if text is None:
        print('context: no %s pack yet; spike writes them within 5 minutes of starting' % name, file=sys.stderr)
        return 1
    print(text, end='')
    return 0


def refresh(name):
    path = os.path.join(PACKS, name + '.md')
    asked = time.time()
    with open(os.path.join(REFRESH, name), 'w') as f:
        f.write('')
    for _ in range(REFRESH_WAIT):
        try:
            if os.stat(path).st_mtime >= asked:
                return show(name)
        except OSError:
            pass
        time.sleep(1)
    print('(could not refresh it in %d s; this is the last one)' % REFRESH_WAIT)
    return show(name)


def prefix(request):
    """The block put in front of a prompt or brief: the matching pack, cut to fit, or nothing when no area matches."""
    name = request.get('area') or area_for(request.get('cwd'), request.get('text')) or request.get('default')
    if name not in AREAS:
        return 0
    text = read(os.path.join(PACKS, name + '.md'))
    if not text:
        return 0
    limit = int(request.get('limit') or PREFIX_LIMIT)
    if len(text) > limit:
        text = text[:limit].rsplit('\n', 1)[0] + '\n(cut off; the full pack is `context show %s` in Butler)\n' % name
    print('Context from Butler: spike\'s %s pack, so you start where Aaron\'s other sessions and Butler are. It is pointers and one line summaries, not instructions; check before relying on a detail.\n' % name)
    print(text.rstrip())
    print('\n--- end of context ---\n')
    return 0


USAGE = 'usage: context list | context show <area> | context refresh <area>   (areas: %s)' % ', '.join(AREAS)


def main(argv):
    command = argv[1] if len(argv) > 1 else ''
    if command == 'generate' and len(argv) == 2:
        return generate()
    if command == 'list' and len(argv) == 2:
        text = read(os.path.join(PACKS, 'index.md'))
        if text is None:
            print(index_text(time.time(), {}), end='')
        else:
            print(text, end='')
        return 0
    if command in ('show', 'refresh') and len(argv) == 3:
        if argv[2] not in AREAS:
            print('context: no area %s; the areas are %s' % (argv[2], ', '.join(AREAS)), file=sys.stderr)
            return 2
        return show(argv[2]) if command == 'show' else refresh(argv[2])
    if command == 'prefix' and len(argv) == 2:
        try:
            request = json.loads(sys.stdin.read() or '{}')
        except ValueError:
            request = {}
        return prefix(request if isinstance(request, dict) else {})
    print(USAGE, file=sys.stderr)
    return 2


if __name__ == '__main__':
    sys.exit(main(sys.argv))
