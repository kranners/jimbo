import base64
import json
import os
import queue
import threading
import socket
import socketserver
import subprocess
import sys
import time

HOSTS = json.loads('@hosts@')
SSH = '@ssh@'
FFMPEG = '@ffmpeg@'
OUTBOX = '@outbox@'
STATE = os.path.expanduser('~/.local/state/mac')
RUNTIME = '/tmp/mac'
PASSWORD = '.local/state/butler-access/vnc-password'
KEEPAWAKE = '/etc/profiles/per-user/$USER/bin/butler-keepawake'
DESKTOP = '/etc/profiles/per-user/$USER/bin/butler-desktop'
BOOT = '/etc/profiles/per-user/$USER/bin/butler-boot'
WAYVNC = 'butler-wayvnc.sock'
WINDOWS_STATE = r'C:\ProgramData\butler-access'
OS_NAMES = {'macos': 'macOS', 'linux': 'Linux', 'windows': 'Windows'}
LIMITS = ('It cannot get past a login screen, a BitLocker or LUKS disk-encryption prompt or a firmware menu, '
          'so if the other system stops at one, Aaron must deal with it at the PC.')
SHOT_WIDTH = 1512
SHOT_DAYS = 1
QUIET = 0.3
FIRST_CHANGE = 1.0
SETTLE_LIMIT = 1.5
CARET_AREA = 4000
RECORD_INTERVAL = 0.5
RECORD_LIMIT = 15 * 60
RECORD_TAIL = 1.5
STREAM_INTERVAL = 0.02
IDLE = 600
DRAG_STEPS = 12
BUTTONS = {'left': 1, 'middle': 2, 'right': 3}
ALIASES = {
    'cmd': 'super', 'command': 'super', 'opt': 'alt', 'option': 'alt',
    'control': 'ctrl', 'return': 'enter', 'escape': 'esc', 'backspace': 'bsp',
    'delete': 'bsp', 'forwarddelete': 'del',
}
TYPED = {'\n': 'enter', '\t': 'tab', ' ': 'space'}

USAGE = '''usage: mac hosts
       mac log [count]
       mac <host> look
       mac <host> click <x> <y> [left|right|middle|double]
       mac <host> move <x> <y>
       mac <host> drag <x1> <y1> <x2> <y2>
       mac <host> scroll <x> <y> <up|down> [clicks]
       mac <host> type [text]          (text on stdin when no arg)
       mac <host> key <combo> [combo...]   (e.g. cmd-space, enter, cmd-shift-t)
       mac <host> windows              (front app, running apps, windows front to back)
       mac <host> run [shell words]    (script on stdin when no arg)
       mac <host> record start | stop
       mac <host> keepawake [status|on|off]
       mac <host> sleep                (keep-awake off, then sleep now)
       mac jimbo boot <linux|windows> [confirm]   (restart into the other system)
x and y are pixels of the last picture from look, whose top-left is 0 0.'''


class Refused(Exception):
    pass


_resolved = {}


def probe(system, found):
    try:
        socket.create_connection((system['address'], 22), timeout=3).close()
        found.put(system)
    except OSError:
        pass


def resolve(host):
    """The system answering for host: a Mac itself, or whichever of jimbo's two installs is up."""
    entry = HOSTS[host]
    if 'systems' not in entry:
        return entry
    if host in _resolved:
        return _resolved[host]
    for system in entry['systems']:
        if subprocess.run(base_args(system, '-O', 'check'), capture_output=True).returncode == 0:
            _resolved[host] = system
            return system
    found = queue.Queue()
    for system in entry['systems']:
        threading.Thread(target=probe, args=(system, found), daemon=True).start()
    try:
        system = found.get(timeout=4)
    except queue.Empty:
        names = ['its %s install (%s)' % (OS_NAMES[s['os']], s['address']) for s in entry['systems']]
        raise Refused('%s is down: %s on ssh; it is off, asleep, at a boot menu or off WireGuard' % (
            host, ('neither ' + ' nor '.join(names) + ' answers') if len(names) > 1 else names[0] + ' does not answer'))
    _resolved[host] = system
    return system


def system_of(host):
    return resolve(host)['os']


def ssh_args(host, *options):
    return base_args(resolve(host), *options)


def base_args(target, *options):
    key = os.path.join(os.environ.get('CREDENTIALS_DIRECTORY', ''), 'butler-mac-key')
    return [
        SSH, '-i', key,
        '-o', 'IdentitiesOnly=yes',
        '-o', 'BatchMode=yes',
        '-o', 'StrictHostKeyChecking=accept-new',
        '-o', 'ConnectTimeout=5',
        '-o', 'Compression=yes',
        '-o', 'ServerAliveInterval=15',
        '-o', 'ControlPath=' + os.path.join(RUNTIME, '%C'),
        '-o', 'StreamLocalBindUnlink=yes',
        *options,
        '%s@%s' % (target['user'], target['address']),
    ]


def control(host, command):
    return subprocess.run(ssh_args(host, '-O', command), capture_output=True, text=True)


def connect_ssh(host):
    os.makedirs(RUNTIME, mode=0o700, exist_ok=True)
    if control(host, 'check').returncode == 0:
        return
    started = subprocess.run(
        ssh_args(host, '-M', '-N', '-f', '-o', 'ControlPersist=600'),
        stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
        text=True, timeout=20, start_new_session=True,
    )
    if started.returncode != 0:
        raise Refused('%s is unreachable over ssh: %s' % (host, started.stderr.strip() or 'no answer'))


# Windows' OpenSSH runs cmd.exe by default, so every Windows command is PowerShell sent on stdin to this bootstrap,
# which keeps quoting and cmd.exe's 8191-character limit out of it.
POWERSHELL_BOOT = (
    "$ProgressPreference = 'SilentlyContinue'; [Console]::InputEncoding = [Text.Encoding]::UTF8; "
    "[Console]::OutputEncoding = [Text.Encoding]::UTF8; $script = [Console]::In.ReadToEnd(); "
    "try { & ([scriptblock]::Create($script)) } catch { [Console]::Error.WriteLine($_); exit 1 }; exit [int]$LASTEXITCODE"
)
POWERSHELL = 'powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand ' + base64.b64encode(
    POWERSHELL_BOOT.encode('utf-16-le')).decode()


def remote(host, command, timeout=50):
    """Runs command on host: a shell command on a Mac or Linux, a PowerShell script on Windows."""
    connect_ssh(host)
    if system_of(host) == 'windows':
        return subprocess.run(ssh_args(host) + [POWERSHELL], input=command, capture_output=True, text=True, timeout=timeout)
    return subprocess.run(
        ssh_args(host) + [command], stdin=subprocess.DEVNULL,
        capture_output=True, text=True, timeout=timeout,
    )


def tunnel(host, far='127.0.0.1:5900'):
    connect_ssh(host)
    path = os.path.join(RUNTIME, '%s-%s.vnc' % (host, system_of(host)))
    forward = '%s:%s' % (path, far)
    control_forward = subprocess.run(ssh_args(host, '-O', 'forward', '-L', forward), capture_output=True, text=True)
    if control_forward.returncode != 0 and 'already' not in control_forward.stderr:
        raise Refused('could not tunnel to %s screen sharing: %s' % (host, control_forward.stderr.strip()))
    return path


def screen(host):
    from vncdotool import api, client as vnc, rfb
    system = system_of(host)
    if system == 'linux':
        # wayvnc listens on a unix socket in Aaron's 0700 runtime directory, which is its only gate, since wayvnc
        # offers vncdotool no password scheme it speaks.
        runtime = remote(host, 'printf %s "$XDG_RUNTIME_DIR"; [ -S "$XDG_RUNTIME_DIR/' + WAYVNC + '" ]')
        if runtime.returncode != 0:
            raise Refused('wayvnc is not running on %s: Hyprland is not up yet, or butler-wayvnc failed (mac %s run systemctl --user status butler-wayvnc)' % (host, host))
        path = tunnel(host, '%s/%s' % (runtime.stdout.strip(), WAYVNC))
        password = None
        rfb.RFBClient.SUPPORTED_AUTHS = {rfb.AuthTypes.NONE}
    else:
        if system == 'windows':
            password = remote(host, "Get-Content -Raw '%s\\vnc-password'" % WINDOWS_STATE)
            missing = '%s has no VNC password yet; Aaron runs docs/windows-remote.ps1 on Windows first' % host
        else:
            password = remote(host, 'cat ' + PASSWORD)
            missing = '%s has no VNC password yet; switch it to jimbo with butler-access' % host
        if password.returncode != 0 or not password.stdout.strip():
            raise Refused(missing)
        password = password.stdout.strip()
        path = tunnel(host)
        rfb.RFBClient.SUPPORTED_AUTHS = {rfb.AuthTypes.VNC_AUTHENTICATION}
    vnc.VNCDoToolClient.encoding = rfb.Encoding.RAW
    from twisted.internet import reactor
    committed = vnc.VNCDoToolClient.commitUpdate

    def request(protocol):
        protocol.streaming = False
        protocol.framebufferUpdateRequest(incremental=1)

    def streamed(protocol, rectangles=None):
        if sum(width * height for _, _, width, height in rectangles or []) > CARET_AREA:
            protocol.changed = time.time()
        committed(protocol, rectangles)
        if not getattr(protocol, 'streaming', False):
            protocol.streaming = True
            reactor.callLater(STREAM_INTERVAL, request, protocol)

    vnc.VNCDoToolClient.commitUpdate = streamed
    client = api.connect(path, password=password, timeout=20)
    client.refreshScreen()
    return client


def scale(client):
    width, _ = client.screen.size
    return max(1.0, width / SHOT_WIDTH)


def point(client, x, y):
    factor = scale(client)
    return round(int(x) * factor), round(int(y) * factor)


def picture(client):
    from PIL import Image
    factor = scale(client)
    width, height = client.screen.size
    image = client.screen.convert('RGB')
    if factor == int(factor):
        return image.reduce(int(factor))
    return image.resize((round(width / factor), round(height / factor)), Image.BILINEAR)


def settle(client, acted):
    while time.time() - acted < SETTLE_LIMIT:
        changed = getattr(client.protocol, 'changed', 0)
        if changed > acted and time.time() - changed >= QUIET:
            return
        if changed <= acted and time.time() - acted >= FIRST_CHANGE:
            return
        time.sleep(0.05)


def look(host, client, acted=None):
    if acted:
        settle(client, acted)
    else:
        time.sleep(0.2)
    image = picture(client)
    os.makedirs(OUTBOX, exist_ok=True)
    cutoff = time.time() - SHOT_DAYS * 86400
    with os.scandir(OUTBOX) as entries:
        for entry in entries:
            if entry.name.startswith('mac-') and entry.name.endswith('.png') and entry.is_file(follow_symlinks=False):
                try:
                    if entry.stat().st_mtime < cutoff:
                        os.remove(entry.path)
                except FileNotFoundError:
                    pass
    path = os.path.join(OUTBOX, 'mac-%s-%s-%03d.png' % (host, time.strftime('%Y%m%d-%H%M%S'), time.time() * 1000 % 1000))
    image.save(path, compress_level=1)
    return '%s (%dx%d, read it to see the screen, or attach it with attach_file)' % (path, image.width, image.height)


def keymap():
    from vncdotool import client as vnc
    vnc.KEYMAP.setdefault('minus', ord('-'))
    return vnc.KEYMAP


def keys(combo):
    parts = combo[:-2].split('-') + ['minus'] if combo.endswith('--') else combo.split('-')
    return '-'.join(ALIASES.get(part.lower(), part.lower() if len(part) > 1 else part) for part in parts)


def act(client, verb, args, stdin=''):
    if verb == 'click':
        x, y = point(client, args[0], args[1])
        how = args[2] if len(args) > 2 else 'left'
        client.mouseMove(x, y)
        for _ in range(2 if how == 'double' else 1):
            client.mousePress(BUTTONS.get(how, 1))
    elif verb == 'move':
        client.mouseMove(*point(client, args[0], args[1]))
    elif verb == 'drag':
        (x1, y1), (x2, y2) = point(client, args[0], args[1]), point(client, args[2], args[3])
        client.mouseMove(x1, y1)
        client.mouseDown(1)
        try:
            for step in range(1, DRAG_STEPS + 1):
                client.mouseMove(x1 + (x2 - x1) * step // DRAG_STEPS, y1 + (y2 - y1) * step // DRAG_STEPS)
                time.sleep(0.03)
        finally:
            client.mouseUp(1)
    elif verb == 'scroll':
        client.mouseMove(*point(client, args[0], args[1]))
        button = 4 if args[2] == 'up' else 5
        for _ in range(int(args[3]) if len(args) > 3 else 3):
            client.mousePress(button)
    elif verb == 'type':
        for character in ' '.join(args) if args else stdin:
            client.keyPress(TYPED.get(character, character))
    elif verb == 'key':
        keymap()
        for combo in args:
            client.keyPress(keys(combo))
    return '%s %s' % (verb, ' '.join(args)) if args else verb


ACTIONS = ('look', 'click', 'move', 'drag', 'scroll', 'type', 'key')
POINTS = {'click': 2, 'move': 2, 'drag': 4, 'scroll': 2}


def check(verb, args, system='macos'):
    needed = POINTS.get(verb, 0)
    if len(args) < needed or not all(arg.isdigit() for arg in args[:needed]):
        raise Refused('%s needs %d whole-number coordinates; see mac --help' % (verb, needed))
    if verb == 'click' and len(args) > 2 and args[2] not in ('left', 'right', 'middle', 'double'):
        raise Refused('click takes left, right, middle or double')
    if verb == 'scroll' and (len(args) < 3 or args[2] not in ('up', 'down') or (len(args) > 3 and not args[3].isdigit())):
        raise Refused('scroll takes <x> <y> <up|down> [clicks]')
    if verb == 'key':
        for combo in args:
            unknown = [part for part in keys(combo).split('-') if len(part) != 1 and part not in keymap()]
            if not combo or unknown:
                raise Refused('unknown key %s in %s' % (', '.join(unknown) or '(empty)', combo))
            if system != 'macos' and {'cmd', 'command'} & set(combo.lower().split('-')):
                raise Refused('%s has no cmd key: use ctrl for shortcuts such as ctrl-c, and super for the Windows or Hyprland key' % OS_NAMES[system])


def session(host):
    return os.path.join(RUNTIME, host + '.session')


def serve(host):
    client = screen(host)

    class Handler(socketserver.StreamRequestHandler):
        def handle(self):
            request = json.loads(self.rfile.readline())
            done = 'nothing'
            try:
                acted = None
                if request['verb'] != 'look':
                    done = act(client, request['verb'], request['args'], request['stdin'])
                    acted = time.time()
                    journal(host, done)
                reply = {'ok': True, 'text': look(host, client, acted)}
                self.server.done = client.screen.size != (client.protocol.width, client.protocol.height)
            except Exception as error:
                self.server.done = True
                reply = {'ok': False, 'did': done, 'text': '%s: %s' % (type(error).__name__, error)}
            self.wfile.write(json.dumps(reply).encode() + b'\n')

    class Server(socketserver.UnixStreamServer):
        timeout = IDLE
        done = False

        def handle_timeout(self):
            self.done = True

    path = session(host)
    server = Server(path + '.new', Handler)
    os.replace(path + '.new', path)
    mine = os.stat(path).st_ino
    try:
        while not server.done:
            server.handle_request()
    finally:
        if os.path.exists(path) and os.stat(path).st_ino == mine:
            os.remove(path)
        client.disconnect()
        from vncdotool import api
        api.shutdown()


def start_session(host, path):
    import fcntl
    with open(os.path.join(RUNTIME, host + '.lock'), 'w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if os.path.exists(path):
            return
        logged = os.path.join(RUNTIME, host + '.log')
        with open(logged, 'w') as log:
            server = subprocess.Popen([sys.argv[0], host, 'serve'], stdin=subprocess.DEVNULL, stdout=log, stderr=log, start_new_session=True)
        deadline = time.time() + 40
        while not os.path.exists(path):
            if server.poll() is not None or time.time() > deadline:
                with open(logged) as failed:
                    lines = failed.read().strip().splitlines()
                raise Refused('could not reach %s screen: %s' % (host, lines[-1] if lines else 'timed out'))
            time.sleep(0.2)


def ask(host, request, retried=False):
    os.makedirs(RUNTIME, mode=0o700, exist_ok=True)
    path = session(host)
    for attempt in range(2):
        start_session(host, path)
        try:
            with socket.socket(socket.AF_UNIX) as connection:
                connection.settimeout(50)
                connection.connect(path)
                connection.sendall(json.dumps(request).encode() + b'\n')
                reply = json.loads(connection.makefile().readline())
            break
        except (ConnectionRefusedError, FileNotFoundError):
            if os.path.exists(path):
                os.remove(path)
    else:
        raise Refused('could not reach %s screen' % host)
    if reply['ok']:
        return reply['text']
    if reply['did'] == 'nothing' and not retried:
        return ask(host, request, retried=True)
    raise Refused('%s (did: %s); the session restarts on the next call' % (reply['text'], reply['did']))


def journal(host, entry):
    os.makedirs(STATE, exist_ok=True)
    with open(os.path.join(STATE, 'actions.jsonl'), 'a') as log:
        log.write(json.dumps({'at': time.strftime('%Y-%m-%dT%H:%M:%S%z'), 'host': host, 'did': entry}) + '\n')


def show_log(count):
    try:
        with open(os.path.join(STATE, 'actions.jsonl')) as log:
            lines = log.readlines()[-count:]
    except FileNotFoundError:
        lines = []
    print(''.join(lines) or 'nothing yet', end='')


MAC_STATUS = 'ioreg -n Root -d1 | grep -c "CGSSessionScreenIsLocked\\"=Yes"; lsappinfo info -only name `lsappinfo front`; %s status 2> /dev/null | head -1' % KEEPAWAKE

LINUX_STATUS = '''
eval "$(%s env 2> /dev/null)"
if pgrep -x hyprlock > /dev/null; then echo LOCKED; else echo unlocked; fi
hyprctl activewindow -j 2> /dev/null | sed -n 's/^ *"class": "\\(.*\\)",$/\\1/p' | head -1 | grep . || echo none
%s status 2> /dev/null | head -1
''' % (DESKTOP, KEEPAWAKE)

WINDOWS_STATUS = r'''
$user = (Get-CimInstance Win32_ComputerSystem).UserName
if (-not $user) { 'AT THE LOGIN SCREEN' } elseif (Get-Process LogonUI -ErrorAction SilentlyContinue) { 'LOCKED' } else { 'unlocked' }
if ($user) { "signed in as $user" } else { 'nobody signed in' }
$file = '%s\keepawake'
"keep-awake: $(if (Test-Path $file) { (Get-Content -Raw $file).Trim() } else { 'on' })"
''' % WINDOWS_STATE


def hosts():
    for host in HOSTS:
        try:
            target = resolve(host)
            system = target['os']
            label = '%s (%s, %s)' % (host, OS_NAMES[system], target['address']) if 'systems' in HOSTS[host] else '%s (%s)' % (host, target['address'])
        except Refused as error:
            print(error)
            continue
        try:
            command = {'macos': MAC_STATUS, 'linux': LINUX_STATUS, 'windows': WINDOWS_STATUS}[system]
            lines = remote(host, command, timeout=15).stdout.splitlines()
            if system == 'macos':
                locked = 'LOCKED' if lines and lines[0].strip() != '0' else 'unlocked'
                front = 'front app ' + (lines[1].split('=', 1)[-1].strip('"') if len(lines) > 1 else 'unknown')
            elif system == 'linux':
                locked = lines[0].strip() if lines else 'unknown'
                front = 'front window ' + (lines[1].strip() if len(lines) > 1 else 'unknown')
            else:
                locked = lines[0].strip() if lines else 'unknown'
                front = lines[1].strip() if len(lines) > 1 else 'unknown'
            awake = lines[2].strip() if len(lines) > 2 else 'keep-awake: not installed'
            print('%s: up, %s, %s, %s' % (label, locked, front, awake))
        except (Refused, subprocess.TimeoutExpired) as error:
            print('%s: down, %s' % (label, error))


# A Linux command gets the Hyprland session's environment, so hyprctl, wl-copy and GUI apps reach Aaron's screen.
LINUX_ENV = 'eval "$(%s env 2> /dev/null)"\n' % DESKTOP


def run(host, words):
    command = ' '.join(words) if words else sys.stdin.read()
    if system_of(host) == 'linux':
        command = LINUX_ENV + command
    try:
        result = remote(host, command)
    except subprocess.TimeoutExpired:
        raise Refused('gave up after 50 s; the command may still be running on %s, so background anything long with its output redirected to a file' % host)
    print(result.stdout, end='')
    if result.stderr:
        print('[stderr]\n' + result.stderr, end='')
    print('[exit %d]' % result.returncode)


WINDOWS = r'''
echo "front: $(lsappinfo info -only name `lsappinfo front` | cut -d= -f2 | tr -d '"')"
echo "apps: $(lsappinfo visibleProcessList | grep -o '"[^"]*"' | tr -d '"' | paste -sd, - | sed 's/,/, /g')"
osascript -l JavaScript <<'EOF'
ObjC.import('CoreGraphics');
ObjC.import('AppKit');
var lines = [];
try {
  var size = $.NSScreen.mainScreen.frame.size;
  lines.push('screen: ' + size.width + 'x' + size.height + ' points');
} catch (error) {}
lines.push('windows, front to back, as app, state, x,y widthxheight in points:');
ObjC.deepUnwrap(ObjC.castRefToObject($.CGWindowListCopyWindowInfo(16, 0))).forEach(function (w) {
  var b = w.kCGWindowBounds;
  if (w.kCGWindowLayer !== 0 || b.Width < 60 || b.Height < 60) return;
  lines.push('  ' + w.kCGWindowOwnerName + ', ' + (w.kCGWindowIsOnscreen ? 'on screen' : 'minimised, hidden or on another space') + ', ' + b.X + ',' + b.Y + ' ' + b.Width + 'x' + b.Height + (w.kCGWindowName ? ', ' + w.kCGWindowName : ''));
});
lines.join('\n');
EOF
'''

# An ssh session on Windows sits in session 0, which sees none of Aaron's windows, so the window list runs as the
# scheduled task butler-desktop in his own session, which docs/windows-remote.ps1 registers.
WINDOWS_WINDOWS = r'''
$dir = '%s'
if (-not (Get-ScheduledTask -TaskName butler-desktop -ErrorAction SilentlyContinue)) {
  [Console]::Error.WriteLine('the butler-desktop task is missing; Aaron runs docs/windows-remote.ps1 again'); exit 3
}
if (-not (Get-CimInstance Win32_ComputerSystem).UserName) { 'nobody is signed in, so there are no windows; look shows the login screen'; exit 0 }
Remove-Item "$dir\desktop.out", "$dir\desktop.done" -ErrorAction SilentlyContinue
Start-ScheduledTask -TaskName butler-desktop
$deadline = (Get-Date).AddSeconds(15)
while (-not (Test-Path "$dir\desktop.done") -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 200 }
if (-not (Test-Path "$dir\desktop.done")) { [Console]::Error.WriteLine('the window list did not come back within 15 s'); exit 4 }
Get-Content -Raw "$dir\desktop.out"
''' % WINDOWS_STATE


def windows(host):
    system = system_of(host)
    command = {'macos': WINDOWS, 'linux': '%s windows' % DESKTOP, 'windows': WINDOWS_WINDOWS}[system]
    result = remote(host, command, timeout=25)
    print(result.stdout, end='')
    if result.returncode != 0:
        raise Refused('could not list the windows on %s: %s' % (host, result.stderr.strip() or 'exit %d' % result.returncode))


# Windows keeps no agent: keep-awake is the power plan's AC timeouts, which Aaron set to never by hand.
WINDOWS_KEEPAWAKE = r'''
$verb = '%s'
$dir = '%s'
$file = "$dir\keepawake"
function Ac($sub, $setting) {
  $query = powercfg /query SCHEME_CURRENT $sub $setting | Out-String
  if ($query -match 'Current AC Power Setting Index:\s+0x([0-9a-fA-F]+)') { $seconds = [Convert]::ToInt32($Matches[1], 16); if ($seconds) { "$([int]($seconds / 60)) min" } else { 'never' } } else { 'unknown' }
}
function Status {
  if (Test-Path $file) { "keep-awake: $((Get-Content -Raw $file).Trim()), set $((Get-Item $file).LastWriteTime.ToString('s'))" } else { 'keep-awake: on, this PC''s default' }
  "on AC: sleep after $(Ac SUB_SLEEP STANDBYIDLE), hibernate after $(Ac SUB_SLEEP HIBERNATEIDLE), display off after $(Ac SUB_VIDEO VIDEOIDLE)"
  "screen: $(if (Get-Process LogonUI -ErrorAction SilentlyContinue) { 'LOCKED or at the login screen' } else { 'unlocked' })"
  'held awake by:'
  powercfg /requests | Where-Object { $_ -and $_ -notmatch '^None\.$' } | ForEach-Object { "  $_" }
}
function Set-To($value, $sleep, $display) {
  New-Item -ItemType Directory -Force $dir | Out-Null
  Set-Content $file $value
  powercfg /change standby-timeout-ac $sleep
  powercfg /change hibernate-timeout-ac 0
  powercfg /change monitor-timeout-ac $display
}
switch ($verb) {
  'on' { Set-To on 0 0; Status }
  'off' { Set-To off 30 10; Status }
  'sleep' {
    Set-To off 30 10
    $action = New-ScheduledTaskAction -Execute powershell.exe -Argument '-NoProfile -WindowStyle Hidden -Command "Start-Sleep 3; Add-Type -AssemblyName System.Windows.Forms; [void][System.Windows.Forms.Application]::SetSuspendState(''Suspend'', $false, $false)"'
    Register-ScheduledTask -TaskName butler-sleep -Action $action -User SYSTEM -RunLevel Highest -Force | Out-Null
    Start-ScheduledTask -TaskName butler-sleep
    'keep-awake off, sleeping in 3 s; it stays off until keepawake on'
  }
  default { Status }
}
'''


def keepawake(host, verb):
    if verb not in ('status', 'on', 'off', 'sleep'):
        raise Refused('keepawake takes status, on or off')
    if verb != 'status':
        journal(host, 'sleep' if verb == 'sleep' else 'keepawake ' + verb)
    if system_of(host) == 'windows':
        result = remote(host, WINDOWS_KEEPAWAKE % (verb, WINDOWS_STATE), timeout=30)
    else:
        result = remote(host, '[ -x %s ] && exec %s %s' % (KEEPAWAKE, KEEPAWAKE, verb), timeout=20)
    if result.returncode != 0 and not result.stdout:
        raise Refused('%s has no keep-awake yet; Aaron switches it to jimbo first' % host)
    print(result.stdout, end='')
    if result.stderr:
        print('[stderr]\n' + result.stderr, end='')


# From Windows: one boot of the firmware's Linux Boot Manager entry (systemd-boot), then a restart.
WINDOWS_BOOT = r'''
$go = %s
$blocks = ((bcdedit /enum firmware) -join "`n") -split "`n\s*`n"
$linux = $blocks | Where-Object { $_ -match 'description\s+(Linux Boot Manager|.*NixOS.*|.*systemd.*)' } | Select-Object -First 1
if (-not $linux -or $linux -notmatch 'identifier\s+(\{[0-9a-fA-F-]+\})') {
  'found no Linux entry in the firmware boot menu; its entries are:'
  $blocks | ForEach-Object { '  ' + ((($_ -split "`n") | Select-String 'identifier|description') -join ', ') }
  exit 3
}
$id = $Matches[1]
$name = if ($linux -match 'description\s+(.+)') { $Matches[1].Trim() } else { $id }
"from Windows: next boot only, start the firmware entry $name $id (bcdedit /set {fwbootmgr} bootsequence $id /addfirst), then restart Windows in 5 s"
if ($go) {
  bcdedit /set '{fwbootmgr}' bootsequence $id /addfirst | Out-Null
  if ($LASTEXITCODE) { [Console]::Error.WriteLine('bcdedit refused the boot sequence'); exit $LASTEXITCODE }
  shutdown.exe /r /t 5 /c 'butler: restarting into Linux, as Aaron asked'
  'restarting into Linux in 5 s'
}
'''


def boot(host, args):
    entry = HOSTS[host]
    if 'systems' not in entry:
        raise Refused('%s runs one system; boot is only for jimbo' % host)
    systems = {system['os']: system for system in entry['systems']}
    if not args or args[0] not in ('linux', 'windows') or args[1:] not in ([], ['confirm']):
        raise Refused('boot takes linux or windows, then confirm to really restart')
    wanted, go = args[0], args[1:] == ['confirm']
    if wanted not in systems:
        raise Refused("spike cannot reach %s's %s install yet, so it would not answer after the restart" % (host, OS_NAMES[wanted]))
    current = system_of(host)
    if current == wanted:
        print('%s is already running %s; nothing to do' % (host, OS_NAMES[wanted]))
        return
    if go:
        journal(host, 'boot %s' % wanted)
    if current == 'windows':
        result = remote(host, WINDOWS_BOOT % ('$true' if go else '$false'), timeout=30)
    else:
        result = remote(host, '%s windows %s' % (BOOT, 'go' if go else 'plan'), timeout=30)
    print(result.stdout, end='')
    if result.stderr:
        print('[stderr]\n' + result.stderr, end='')
    print(LIMITS)
    if result.returncode != 0:
        raise Refused('the boot switch failed on %s (exit %d); nothing was restarted' % (OS_NAMES[current], result.returncode))
    if not go:
        raise Refused('nothing done yet: run mac %s boot %s confirm only once Aaron has asked for it' % (host, wanted))
    print('%s goes down now and should answer as %s in a minute or two; poll mac hosts' % (host, OS_NAMES[wanted]))


def recording(host):
    return os.path.join(RUNTIME, 'record-' + host)


def alive(folder):
    try:
        with open(os.path.join(folder, 'pid')) as pid:
            os.kill(int(pid.read()), 0)
        return True
    except (FileNotFoundError, ValueError, ProcessLookupError):
        return False


def outcome(folder):
    try:
        with open(os.path.join(folder, 'result')) as result:
            return result.read().strip()
    except FileNotFoundError:
        return None


def record(host, verb):
    folder = recording(host)
    os.makedirs(os.path.join(folder, 'frames'), exist_ok=True)
    if verb == 'start':
        if alive(folder):
            raise Refused('already recording %s; mac %s record stop first' % (host, host))
        for name in ('stop', 'result', 'pid'):
            if os.path.exists(os.path.join(folder, name)):
                os.remove(os.path.join(folder, name))
        with open(os.path.join(folder, 'log'), 'w') as log:
            loop = subprocess.Popen([sys.argv[0], host, 'record', 'loop'], stdin=subprocess.DEVNULL, stdout=log, stderr=log, start_new_session=True)
        with open(os.path.join(folder, 'pid'), 'w') as pid:
            pid.write(str(loop.pid))
        deadline = time.time() + 30
        while not os.path.exists(os.path.join(folder, 'recording')):
            if loop.poll() is not None or time.time() > deadline:
                raise Refused('could not start recording %s: %s' % (host, outcome(folder) or 'timed out'))
            time.sleep(0.2)
        print('recording %s, at most %d minutes; mac %s record stop to get the video' % (host, RECORD_LIMIT // 60, host))
    elif verb == 'stop':
        if not alive(folder):
            print(outcome(folder) or 'not recording %s' % host)
            return
        time.sleep(RECORD_TAIL)
        open(os.path.join(folder, 'stop'), 'w').close()
        deadline = time.time() + 53
        while alive(folder) and time.time() < deadline:
            time.sleep(0.5)
        print(outcome(folder) or 'still encoding; run mac %s record stop again shortly for the path' % host)
    elif verb == 'loop':
        record_loop(host, folder)


def record_loop(host, folder):
    frames = os.path.join(folder, 'frames')
    stamps = []
    result = 'recording failed'
    try:
        client = screen(host)
        open(os.path.join(folder, 'recording'), 'w').close()
        started = time.time()
        while not os.path.exists(os.path.join(folder, 'stop')) and time.time() - started < RECORD_LIMIT:
            image = picture(client)
            image = image.crop((0, 0, image.width - image.width % 2, image.height - image.height % 2))
            stamps.append(time.time())
            image.save(os.path.join(frames, '%06d.jpg' % len(stamps)), quality=85)
            time.sleep(max(0, RECORD_INTERVAL - (time.time() - stamps[-1])))
        client.disconnect()
        listing = os.path.join(folder, 'frames.txt')
        with open(listing, 'w') as out:
            for index, stamp in enumerate(stamps, 1):
                following = stamps[index] if index < len(stamps) else stamp + RECORD_INTERVAL
                out.write("file '%s'\nduration %.3f\n" % (os.path.join(frames, '%06d.jpg' % index), following - stamp))
        os.makedirs(OUTBOX, exist_ok=True)
        video = os.path.join(OUTBOX, 'mac-%s-%s.mp4' % (host, time.strftime('%Y%m%d-%H%M%S')))
        subprocess.run(
            [FFMPEG, '-loglevel', 'error', '-f', 'concat', '-safe', '0', '-i', listing,
             '-fps_mode', 'vfr', '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '28',
             '-pix_fmt', 'yuv420p', '-movflags', '+faststart', video],
            check=True,
        )
        journal(host, 'recorded %s' % video)
        result = 'saved %s, %d s, attach it with attach_file' % (video, round(stamps[-1] - stamps[0]))
    except Exception as error:
        result = 'recording failed: %s: %s' % (type(error).__name__, error)
        raise
    finally:
        with open(os.path.join(folder, 'result'), 'w') as out:
            out.write(result + '\n')
        for name in os.listdir(frames):
            os.remove(os.path.join(frames, name))
        for name in ('recording', 'stop'):
            if os.path.exists(os.path.join(folder, name)):
                os.remove(os.path.join(folder, name))
        from vncdotool import api
        api.shutdown()


def main():
    args = sys.argv[1:]
    if args[:1] == ['hosts']:
        return hosts()
    if args[:1] == ['log']:
        return show_log(int(args[1]) if len(args) > 1 else 20)
    if len(args) < 2 or args[0] not in HOSTS:
        print(USAGE, file=sys.stderr)
        print('hosts: ' + ', '.join(HOSTS), file=sys.stderr)
        return 2
    host, verb, rest = args[0], args[1], args[2:]
    if verb == 'run':
        journal(host, 'run ' + (' '.join(rest) or '(script on stdin)'))
        return run(host, rest)
    if verb == 'windows':
        return windows(host)
    if verb == 'record':
        return record(host, rest[0] if rest else '')
    if verb == 'keepawake':
        return keepawake(host, rest[0] if rest else 'status')
    if verb == 'sleep':
        return keepawake(host, 'sleep')
    if verb == 'boot':
        return boot(host, rest)
    if verb == 'serve':
        return serve(host)
    if verb not in ACTIONS:
        print(USAGE, file=sys.stderr)
        return 2
    check(verb, rest, system_of(host) if verb == 'key' else 'macos')
    stdin = sys.stdin.read() if verb == 'type' and not rest else ''
    wide = sorted({character for character in ' '.join(rest) + stdin if ord(character) > 0xFF})
    if wide:
        raise Refused('type sends Latin-1 only, not %s; on a Mac run pbcopy with the text on stdin, then key cmd-v; on Linux run wl-copy with it, then key ctrl-v' % ' '.join(wide))
    print(ask(host, {'verb': verb, 'args': rest, 'stdin': stdin}))


if __name__ == '__main__':
    try:
        sys.exit(main())
    except Refused as error:
        print('mac: %s' % error, file=sys.stderr)
        sys.exit(75)
