# mac <host> push: copies a file butler may attach from spike to a Mac's ~/butler-drop, or a named folder in ~/Downloads.
# The daemon judges each push first, by the same rule as attach_file: only files under butler's attach and read roots, or
# its thread's own scratch folder, never a secret, and a sensitive document only on Aaron's own named request under a
# mission listing it, when it tells this command so in BUTLER_PUSH_SENSITIVE and BUTLER_PUSH_FILE. A sensitive copy on
# the Mac is deleted 30 minutes later unless that mission item says keep, which the daemon passes as BUTLER_PUSH_KEEP.
# mac.py takes this file in place of its @push@ line, without the imports, which it already has; test_push.py imports it.
import json
import os
import re
import shlex
import time

PUSH_TTL = 30 * 60
PUSH_DENIED_PREFIXES = ('/var/lib/secrets', '/run', '/etc', '/proc', '/sys', '/dev', '/home', '/root', '/Users', '/boot', '/var/lib/private')
PUSH_SECRET_NAME = re.compile(r'token|secret|passw(?:or)?d|credential|cookie|private[-_ ]?key|^id_(?:rsa|ed25519|ecdsa|dsa)|\.(?:pem|key|p12|pfx|kdbx|keychain|gpg|asc)$|^\.env|^\.netrc$|^known_hosts$|^authorized_keys$', re.I)
PUSH_SENSITIVE_WORDS = re.compile(r'(?:^|[^a-z])(?:passports?|licen[cs]es?|medicare|tax|bank)', re.I)
PUSH_FOLDER = re.compile(r'^[A-Za-z0-9][A-Za-z0-9._ ()+,-]{0,99}$')


class PushRefused(Exception):
    pass


def push_under(path, root):
    return path == root or path.startswith(root.rstrip('/') + '/')


def push_real_roots(roots):
    out = []
    for root in roots:
        if os.path.isabs(root) and os.path.exists(root):
            out.append(os.path.realpath(root))
    return out


def push_check(target, rest, env, roots, sensitive_roots, scratch_dir, limit):
    """What one push copies, and where: the resolved file, the folder in ~/Downloads or None for ~/butler-drop, whether it
    is sensitive and whether it is kept. Refuses anything the daemon's rule would."""
    if not target or not os.path.isabs(target):
        raise PushRefused('usage: mac <host> push <absolute spike path> [folder in ~/Downloads] [keep]')
    keep_word = 'keep' in rest
    words = [w for w in rest if w != 'keep']
    if len(words) > 1:
        raise PushRefused('usage: mac <host> push <absolute spike path> [folder in ~/Downloads] [keep]')
    folder = words[0] if words else None
    if folder is not None and (not PUSH_FOLDER.match(folder) or folder in ('.', '..')):
        raise PushRefused('the folder is one name in ~/Downloads, letters, digits, spaces and . _ ( ) + , - only, not %s' % folder)
    path = os.path.realpath(target)
    if not os.path.isfile(path):
        raise PushRefused('not a file on spike: %s' % target)
    thread = re.sub(r'[^0-9A-Za-z_-]', '', env.get('BUTLER_THREAD_ID', ''))[:32]
    allowed = push_real_roots(roots) + (push_real_roots([os.path.join(scratch_dir, thread)]) if scratch_dir and thread else [])
    if any(push_under(path, p) for p in PUSH_DENIED_PREFIXES):
        raise PushRefused("secrets, credential stores, system folders and other users' homes are never sent")
    root = next((r for r in allowed if push_under(path, r)), None)
    if root is None:
        raise PushRefused('only files butler may attach can be pushed, under %s or its thread\'s scratch folder' % ', '.join(roots))
    below = os.path.relpath(path, root)
    parts = [p for p in below.split('/') if p]
    if any(p.startswith('.') for p in parts):
        raise PushRefused('hidden files and folders, such as .git or .ssh, are never sent')
    if any(PUSH_SECRET_NAME.search(p) for p in parts):
        raise PushRefused('a file named like a token, key, password or credential is never sent')
    size = os.path.getsize(path)
    if size > limit:
        raise PushRefused('%s is %d MB, over the %d MB push limit' % (path, size >> 20, limit >> 20))
    sensitive = bool(PUSH_SENSITIVE_WORDS.search(below)) or any(push_under(path, r) for r in push_real_roots(sensitive_roots))
    if sensitive and (env.get('BUTLER_PUSH_SENSITIVE') != '1' or env.get('BUTLER_PUSH_FILE') != path):
        raise PushRefused('%s is a sensitive document, pushed only once the daemon has cleared it: Aaron\'s own message naming it and a mission item listing it' % os.path.basename(path))
    keep = keep_word and (not sensitive or env.get('BUTLER_PUSH_KEEP') == '1')
    return {'path': path, 'size': size, 'folder': folder, 'sensitive': sensitive, 'keep': keep}


def push_script(plan, ttl=PUSH_TTL):
    """The sh run on the Mac, which reads the file on stdin, writes it in place through a partial and prints its path, and,
    for a sensitive copy not kept, deletes it again after ttl seconds."""
    name = os.path.basename(plan['path'])
    folder = plan['folder']
    lines = [
        'set -e',
        'umask 077',
        'h=$(cd && pwd -P)',
        'd="$h/butler-drop"' if folder is None else 'd="$h/Downloads/"%s' % shlex.quote(folder),
        '[ ! -L "$d" ] || { echo "$d is a symlink" >&2; exit 4; }',
        'mkdir -p "$d"',
        'r=$(cd "$d" && pwd -P)',
        'case "$r/" in "$h/butler-drop/"*|"$h/Downloads/"?*) ;; *) echo "only ~/butler-drop or a folder in ~/Downloads, not $r" >&2; exit 4 ;; esac',
        'n=%s' % shlex.quote(name),
        'f="$r/$n"',
        '[ ! -e "$f" ] && [ ! -L "$f" ] || f="$r/$(date +%Y%m%d-%H%M%S)-$n"',
        'cat > "$f.partial"',
        'mv -f "$f.partial" "$f"',
        'printf "%s\\n" "$f"',
    ]
    if plan['sensitive'] and not plan['keep']:
        lines.append('nohup sh -c \'sleep %d; rm -f -- "$1"\' sh "$f" </dev/null >/dev/null 2>&1 &' % int(ttl))
    return '\n'.join(lines) + '\n'


def push_pending_add(state_file, host, path, due):
    """Records a copy to delete, so a Mac that slept through its own timer is cleaned on the next push to it."""
    data = push_pending_load(state_file)
    data.append({'host': host, 'path': path, 'due': due})
    push_pending_save(state_file, data)


def push_pending_due(state_file, host, now):
    """The copies on host past their time, which are dropped from the record."""
    data = push_pending_load(state_file)
    due = [e['path'] for e in data if e['host'] == host and e['due'] <= now]
    push_pending_save(state_file, [e for e in data if not (e['host'] == host and e['due'] <= now)])
    return due


def push_pending_load(state_file):
    try:
        with open(state_file) as handle:
            data = json.load(handle)
        return data if isinstance(data, list) else []
    except (OSError, ValueError):
        return []


def push_pending_save(state_file, data):
    os.makedirs(os.path.dirname(state_file), exist_ok=True)
    partial = state_file + '.partial'
    with open(partial, 'w') as handle:
        json.dump(data, handle)
    os.replace(partial, state_file)


def push_cleanup_script(paths):
    """Deletes copies whose time has passed, only inside ~/butler-drop or ~/Downloads."""
    quoted = ' '.join(shlex.quote(p) for p in paths)
    return ('h=$(cd && pwd -P)\nfor f in %s; do case "$f" in "$h/butler-drop/"*|"$h/Downloads/"*) rm -f -- "$f" ;; esac; done\n' % quoted)


def push_run(plan, host, run, state_file, now=None, ttl=PUSH_TTL):
    """Copies the planned file to host. run(script, stdin_path) runs sh there and returns (code, stdout, stderr)."""
    now = time.time() if now is None else now
    due = push_pending_due(state_file, host, now)
    if due:
        run(push_cleanup_script(due), None)
    code, out, err = run(push_script(plan, ttl), plan['path'])
    lines = out.strip().splitlines()
    if code != 0 or not lines:
        raise PushRefused('copying %s to %s failed: %s' % (plan['path'], host, err.strip() or 'exit %d' % code))
    placed = lines[-1]
    if plan['sensitive'] and not plan['keep']:
        push_pending_add(state_file, host, placed, now + ttl)
    return placed
