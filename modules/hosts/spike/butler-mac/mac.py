import base64
import fcntl
import json
import os
import queue
import re
import shlex
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
WINDOWS_SHOT_INSTALLER = '@windowsScreenshot@'
HELPER_PORT = '@helperPort@'
# Rectangle's URL scheme actions, from its README; each acts on the front window, as his keyboard shortcuts do.
RECTANGLE_ACTIONS = '''left-half right-half center-half top-half bottom-half top-left top-right bottom-left bottom-right first-third center-third last-third first-two-thirds last-two-thirds maximize almost-maximize maximize-height smaller larger center center-prominently restore next-display previous-display move-left move-right move-up move-down first-fourth second-fourth third-fourth last-fourth first-three-fourths last-three-fourths top-left-sixth top-center-sixth top-right-sixth bottom-left-sixth bottom-center-sixth bottom-right-sixth top-left-ninth top-center-ninth top-right-ninth middle-left-ninth middle-center-ninth middle-right-ninth bottom-left-ninth bottom-center-ninth bottom-right-ninth top-left-third top-right-third bottom-left-third bottom-right-third top-left-eighth top-center-left-eighth top-center-right-eighth top-right-eighth bottom-left-eighth bottom-center-left-eighth bottom-center-right-eighth bottom-right-eighth tile-all tile-rows tile-columns cascade-all cascade-active-app'''.split()
STATE = os.path.expanduser('~/.local/state/mac')
RUNTIME = '/tmp/mac'
PASSWORD = '.local/state/butler-access/vnc-password'
KEEPAWAKE = '/etc/profiles/per-user/$USER/bin/butler-keepawake'
DESKTOP = '/etc/profiles/per-user/$USER/bin/butler-desktop'
BOOT = '/etc/profiles/per-user/$USER/bin/butler-boot'
WAYVNC = 'butler-wayvnc.sock'
WINDOWS_STATE = r'C:\ProgramData\butler-access'
OVERLAY = '/etc/profiles/per-user/$USER/bin/butler-overlay'
MEMORY_AUDIT = '@memoryAudit@'
# fetch copies a file from a Mac's or Linux jimbo's ~/Downloads or ~/butler-drop into this spool, under butler's
# ~/.cache, which its Read is denied, and butler-index-drop, as butler outside the daemon's sandbox, checks it and
# moves it into the index inbox, answering in the results folder beside it.
DROP = '@drop@'
DROP_MAX = @dropMax@
# Never from pilot, Aaron's employer's Mac, unless he changes this himself.
DROP_HOSTS = ('piggys-MBP', 'jimbo')
# The machines monitor's expected-off marks: sleeping, booting or letting a machine idle tells it to say nothing about it.
EXPECTED = '@expected@'
# A control session ends after this many seconds without a mac command, as the overlay on the Mac does by itself.
CONTROL_IDLE = @idle@
CONTROL = os.path.join(STATE, 'control')
AUDIT_SPOOL = os.path.join(STATE, 'audit-spool')
SAY_LIMIT = 160
# An automatic bubble waits this long after butler's own words, so it never buries them.
QUIET_AFTER_SAY = 8
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
HANDSHAKE_TIMEOUT = 20
# The first frame is the whole screen in raw pixels, 29 MB on jimbo's 5120x1440 monitor, so it gets a second per
# megabyte on top of the handshake's 20 s, and start_session waits for both.
FRAME_TIMEOUT = 20
# Windows sends no frames over VNC, which carries only input there: each picture is a screenshot its butler-screenshot
# task takes on Aaron's desktop, already scaled down, so a look waits a fixed moment after an action instead.
WINDOWS_SHOT_TIMEOUT = 15
WINDOWS_SETTLE = 0.6
START_TIMEOUT = 90
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
       mac <host> say [text]           (a speech bubble on the Mac's overlay; text on stdin when no arg)
       mac <host> done                 (hand control back: the overlay fades out)
       mac <host> click <x> <y> [left|right|middle|double]
       mac <host> move <x> <y>
       mac <host> drag <x1> <y1> <x2> <y2>
       mac <host> scroll <x> <y> <up|down> [clicks]
       mac <host> type [text]          (text on stdin when no arg)
       mac <host> key <combo> [combo...]   (e.g. cmd-space, enter, cmd-shift-t)
       mac <host> windows              (front app, running apps, windows front to back)
       mac <host> run [shell words]    (script on stdin when no arg)
       mac <host> record start | stop
       mac <host> confirm "<what will happen>" <action...>   (an action the outcome check refused, once Aaron said yes)
       mac <host> keepawake [status|on|off]
       mac <host> fetch <file> <inbox folder> [name]   (copy a file from ~/Downloads or ~/butler-drop into spike's index inbox)
       mac <host> push <spike path> [folder] [keep]   (copy a file butler may attach to ~/butler-drop, or ~/Downloads/<folder>)
       mac <host> sleep                (keep-awake off, then sleep now)
       mac jimbo boot <linux|windows> [confirm]   (restart into the other system)
Macs only, through the Hammerspoon helper butler-access installs:
       mac <host> menu <app|front> [menu] [item...]   (list an app's menus, or choose an item by name)
       mac <host> dialog [app]         (the front window's controls, numbered)
       mac <host> press <number|name> [app]   (press a button, checkbox, pop-up or link of dialog)
       mac <host> focus <number|name> [app]   (put the keyboard in a field of dialog, for type)
       mac <host> displays             (every display, numbered, 1 being the one with the menu bar)
       mac <host> display <n> [look]   (a picture of one display)
       mac <host> display <n> click <x> <y> [left|right|double]   (x and y are pixels of that picture)
       mac <host> window <rectangle action>   (e.g. left-half, maximize, next-display, first-third)
       mac <host> window display <n>   (move the front window onto display n)
x and y are pixels of the last picture from look, whose top-left is 0 0.'''


class Refused(Exception):
    pass


class Lost(Refused):
    """The machine stopped answering, which ends a control session as its connection closed."""


_resolved = {}


PRESENCE = os.path.join(STATE, 'presence')
# @presence@

# @push@

# What push may copy from spike, the daemon's attach roots and read roots, the identity documents among them, and
# each thread's scratch folder; the daemon judges every push first, and this checks again.
PUSH_ROOTS = json.loads('@pushRoots@')
PUSH_SENSITIVE_ROOTS = json.loads('@pushSensitiveRoots@')
PUSH_SCRATCH = '@scratch@'
PUSHED = os.path.join(STATE, 'pushed.json')


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
        raise Lost('%s is down: %s on ssh; it is off, asleep, at a boot menu or off WireGuard' % (
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
        raise Lost('%s is unreachable over ssh: %s' % (host, started.stderr.strip() or 'no answer'))


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


def hello(host, far):
    """Reads the VNC server's greeting over a fresh ssh channel, to say why a handshake through the tunnel failed."""
    import select
    probe = subprocess.Popen(ssh_args(host, '-W', far), stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        ready, _, _ = select.select([probe.stdout], [], [], 8)
        greeting = os.read(probe.stdout.fileno(), 12) if ready else None
    finally:
        probe.kill()
        _, err = probe.communicate(timeout=5)
    err = ' '.join(err.decode(errors='replace').split())
    if greeting is None:
        return 'nothing answered on %s within 8 s' % far
    if not greeting:
        return 'ssh could not open a channel to %s%s' % (far, ': ' + err if err else ', so sshd refuses port forwarding for butler\'s key or nothing listens there')
    return 'the server there greets with %r' % greeting.decode(errors='replace').strip()


class Handshake:
    """Collects vncdotool's protocol log, which it otherwise drops, and turns a connection the server closes before
    the handshake ends into an error, where vncdotool would wait for its timeout without saying why."""

    def __init__(self):
        import collections
        import logging
        self.lines = collections.deque(maxlen=6)
        handler = logging.Handler(logging.INFO)
        handler.emit = lambda record: self.lines.append(record.getMessage())
        logger = logging.getLogger('twisted')
        logger.setLevel(logging.INFO)
        logger.addHandler(handler)

    def said(self):
        return '; '.join(line for line in self.lines if not line.startswith(('x=', 'Native ', 'Starting factory', 'Stopping factory'))) or 'nothing'

    def factory(self):
        from vncdotool import client as vnc
        handshake = self

        class Factory(vnc.VNCDoToolFactory):
            def clientConnectionLost(self, connector, reason):
                if not self.deferred.called:
                    self.deferred.errback(ConnectionError('the VNC server closed the connection during the handshake (it said: %s)' % handshake.said()))

        return Factory


def screen(host):
    """Connects to host's screen, saying which stage failed: ssh, the tunnel, the VNC handshake or the first frame."""
    stage = ['ssh']
    try:
        return open_screen(host, stage)
    except Refused:
        raise
    except Exception as error:
        raise Refused('%s failed: %s: %s' % (stage[0], type(error).__name__, error))


def open_screen(host, stage):
    from vncdotool import api, client as vnc, rfb
    system = system_of(host)
    far = '127.0.0.1:5900'
    if system == 'linux':
        # wayvnc listens on a unix socket in Aaron's 0700 runtime directory, which is its only gate, since wayvnc
        # offers vncdotool no password scheme it speaks.
        runtime = remote(host, 'printf %s "$XDG_RUNTIME_DIR"; [ -S "$XDG_RUNTIME_DIR/' + WAYVNC + '" ]')
        if runtime.returncode != 0:
            raise Refused('wayvnc is not running on %s: Hyprland is not up yet, or butler-wayvnc failed (mac %s run systemctl --user status butler-wayvnc)' % (host, host))
        far = '%s/%s' % (runtime.stdout.strip(), WAYVNC)
        stage[0] = 'ssh tunnel'
        path = tunnel(host, far)
        password = None
        rfb.RFBClient.SUPPORTED_AUTHS = {rfb.AuthTypes.NONE}
    else:
        if system == 'windows':
            stage[0] = 'installing the butler-screenshot task'
            with open(WINDOWS_SHOT_INSTALLER) as installer:
                installed = remote(host, installer.read(), timeout=40)
            if installed.returncode != 0:
                raise Refused('could not install the butler-screenshot task on %s: %s; Aaron runs docs/windows-screenshot.ps1 in an administrator PowerShell' % (
                    host, ' '.join((installed.stderr or installed.stdout).split()) or 'exit %d' % installed.returncode))
            stage[0] = 'reading the VNC password'
            password = remote(host, "Get-Content -Raw '%s\\vnc-password'" % WINDOWS_STATE)
            missing = '%s has no VNC password yet; Aaron runs docs/windows-remote.ps1 on Windows first' % host
        else:
            password = remote(host, 'cat ' + PASSWORD)
            missing = '%s has no VNC password yet; switch it to jimbo with butler-access' % host
        if password.returncode != 0 or not password.stdout.strip():
            raise Refused(missing)
        # Windows PowerShell can start its output with a byte-order mark, which strip() keeps.
        password = password.stdout.replace('\ufeff', '').strip()
        stage[0] = 'ssh tunnel'
        path = tunnel(host, far)
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
    stage[0] = 'VNC handshake'
    handshake = Handshake()
    client = api.connect(path, password=password, timeout=HANDSHAKE_TIMEOUT, factory_class=handshake.factory())
    try:
        client.pause(0)
    except Exception as error:
        why = '%s: %s' % (type(error).__name__, error)
        if isinstance(error, TimeoutError):
            why = 'the VNC handshake did not finish in %d s (the server said: %s)' % (HANDSHAKE_TIMEOUT, handshake.said())
        elif not isinstance(error, ConnectionError):
            why = 'the VNC handshake failed: ' + why
        if system != 'linux':
            why += '; %s' % hello(host, far)
        raise Refused(why)
    width, height = client.protocol.width, client.protocol.height
    if system == 'windows':
        # VNC is for input alone here; pictures come from the PC, see windows_picture.
        client.__dict__['shot_host'] = host
        stage[0] = 'first screenshot'
        windows_picture(client)
        return client
    stage[0] = 'first VNC frame'
    client.timeout = FRAME_TIMEOUT + width * height * 4 / 1e6
    try:
        client.refreshScreen()
    except TimeoutError:
        raise Refused('the VNC server at %dx%d sent no whole frame within %d s' % (width, height, client.timeout))
    client.timeout = HANDSHAKE_TIMEOUT
    return client


def size(client):
    """The screen's size in real pixels, the coordinates VNC input takes."""
    if client.__dict__.get('shot_host'):
        return client.protocol.width, client.protocol.height
    return client.screen.size


def scale(client):
    width, _ = size(client)
    return max(1.0, width / SHOT_WIDTH)


def target(client):
    width, height = size(client)
    factor = scale(client)
    return round(width / factor), round(height / factor)


# Runs as Aaron's butler-screenshot task on his own desktop, from docs/windows-screenshot.ps1, and prints its result:
# a line `ok <width> <height>` of the real screen, then the PNG in base64.
WINDOWS_SHOT = r'''
$dir = '%s'
Remove-Item "$dir\shot.done", "$dir\shot.out", "$dir\shot.png" -ErrorAction SilentlyContinue
Set-Content "$dir\shot.request" '%d %d'
$run = & schtasks.exe /run /tn butler-screenshot 2>&1
if ($LASTEXITCODE) { [Console]::Error.WriteLine("could not start the butler-screenshot task: $run"); exit 3 }
$deadline = (Get-Date).AddSeconds(%d)
while (-not (Test-Path "$dir\shot.done") -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 50 }
$said = if (Test-Path "$dir\shot.out") { (Get-Content -Raw "$dir\shot.out").Trim() } else { '' }
if ($said -like 'ok *' -and (Test-Path "$dir\shot.png")) { $said; [Convert]::ToBase64String([IO.File]::ReadAllBytes("$dir\shot.png")); exit 0 }
$user = (Get-CimInstance Win32_ComputerSystem).UserName
$why = if (-not $user) { 'nobody is signed in, so the PC is at its login screen, which only Aaron passes' }
  elseif (Get-Process LogonUI -ErrorAction SilentlyContinue) { 'the PC is locked, which only Aaron undoes at the PC' }
  elseif (-not (Test-Path "$dir\shot.done")) { "the butler-screenshot task did not finish within %d s" }
  else { "the capture on Aaron's desktop failed: $said" }
[Console]::Error.WriteLine($why)
exit 4
'''


def windows_picture(client):
    import io
    from PIL import Image
    host = client.__dict__['shot_host']
    width, height = target(client)
    result = remote(host, WINDOWS_SHOT % (WINDOWS_STATE, width, height, WINDOWS_SHOT_TIMEOUT, WINDOWS_SHOT_TIMEOUT), timeout=WINDOWS_SHOT_TIMEOUT + 20)
    lines = result.stdout.split()
    if result.returncode != 0 or len(lines) < 4 or lines[0] != 'ok':
        raise Refused('the screenshot on %s failed: %s' % (host, ' '.join(result.stderr.split()) or 'exit %d, %s' % (result.returncode, ' '.join(lines[:3]) or 'no output')))
    client.__dict__['shot_source'] = (int(lines[1]), int(lines[2]))
    image = Image.open(io.BytesIO(base64.b64decode(''.join(lines[3:])))).convert('RGB')
    if image.size != (width, height):
        image = image.resize((width, height), Image.BILINEAR)
    return image


def point(client, x, y):
    factor = scale(client)
    return round(int(x) * factor), round(int(y) * factor)


def picture(client):
    from PIL import Image
    if client.__dict__.get('shot_host'):
        return windows_picture(client)
    factor = scale(client)
    width, height = client.screen.size
    image = client.screen.convert('RGB')
    if factor == int(factor):
        return image.reduce(int(factor))
    return image.resize((round(width / factor), round(height / factor)), Image.BILINEAR)


def settle(client, acted):
    if client.__dict__.get('shot_host'):
        time.sleep(max(0, WINDOWS_SETTLE - (time.time() - acted)))
        return
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
    path = outbox_picture(host)
    image.save(path, compress_level=1)
    return '%s (%dx%d, read it to see the screen, or attach it with attach_file)' % (path, image.width, image.height)


def outbox_picture(host, kind=''):
    """A fresh outbox path for a screenshot, pruning screenshots over SHOT_DAYS old."""
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
    return os.path.join(OUTBOX, 'mac-%s%s-%s-%03d.png' % (host, kind, time.strftime('%Y%m%d-%H%M%S'), time.time() * 1000 % 1000))


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
        typed = ' '.join(args) if args else stdin
        for character in typed:
            client.keyPress(TYPED.get(character, character))
        # What was typed may be private, so the log says only how much.
        return 'type (%d characters)' % len(typed)
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
            stage = 'screenshot'
            try:
                acted = None
                if request['verb'] != 'look':
                    stage = 'input'
                    done = act(client, request['verb'], request['args'], request['stdin'])
                    acted = time.time()
                    journal(host, done)
                    stage = 'screenshot'
                reply = {'ok': True, 'text': look(host, client, acted)}
                if client.__dict__.get('shot_host'):
                    # The PC's screen changed size since VNC connected, so input would land in the wrong place.
                    self.server.done = client.__dict__.get('shot_source') != size(client)
                else:
                    self.server.done = client.screen.size != (client.protocol.width, client.protocol.height)
            except Exception as error:
                self.server.done = True
                self.server.failed = True
                why = str(error) if isinstance(error, Refused) else '%s: %s' % (type(error).__name__, error)
                reply = {'ok': False, 'did': done, 'text': '%s failed: %s' % (stage, why)}
            self.wfile.write(json.dumps(reply).encode() + b'\n')

    class Server(socketserver.UnixStreamServer):
        timeout = IDLE
        done = False
        failed = False

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
        if server.failed:
            end(host, 'connection closed')


def start_session(host, path):
    import fcntl
    with open(os.path.join(RUNTIME, host + '.lock'), 'w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if os.path.exists(path):
            return
        logged = os.path.join(RUNTIME, host + '.log')
        with open(logged, 'w') as log:
            server = subprocess.Popen([sys.argv[0], host, 'serve'], stdin=subprocess.DEVNULL, stdout=log, stderr=log, start_new_session=True)
        deadline = time.time() + START_TIMEOUT
        while not os.path.exists(path):
            if server.poll() is not None or time.time() > deadline:
                with open(logged) as failed:
                    lines = failed.read().strip().splitlines()
                last = lines[-1] if lines else 'timed out after %d s' % START_TIMEOUT
                raise Lost('could not reach %s screen: %s' % (host, last[len('mac: '):] if last.startswith('mac: ') else last))
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
        raise Lost('could not reach %s screen' % host)
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


# butler-access's Hammerspoon watcher keeps the current lock's time and cause in last-lock, which an unlock removes.
MAC_STATUS = ('ioreg -n Root -d1 | grep -c "CGSSessionScreenIsLocked\\"=Yes"; lsappinfo info -only name `lsappinfo front`; '
              '%s status 2> /dev/null | head -1; echo "lock: $(head -1 ~/.local/state/butler-access/last-lock 2> /dev/null)"' % KEEPAWAKE)

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
            why = [line[len('lock: '):].split('\t') for line in lines if line.startswith('lock: ')]
            lines = [line for line in lines if not line.startswith('lock: ')]
            if system == 'macos':
                locked = 'LOCKED' if lines and lines[0].strip() != '0' else 'unlocked'
                if locked == 'LOCKED':
                    locked += (' at %s: %s' % (why[0][1], why[0][2])) if why and len(why[0]) == 3 else ' (no lock recorded)'
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


def run(host, words, stdin=''):
    command = ' '.join(words) if words else stdin
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


FETCH_RESOLVE = r"""
p=%s
case "$p" in
  '~/'*) p="$HOME/${p#??}" ;;
  /*) ;;
  *) p="$HOME/Downloads/$p" ;;
esac
if [ -L "$p" ] || [ ! -f "$p" ]; then echo "not a regular file: $p" >&2; exit 3; fi
d=$(cd "$(dirname "$p")" && pwd -P) || exit 3
h=$(cd && pwd -P)
case "$d/" in
  "$h/Downloads/"*|"$h/butler-drop/"*) ;;
  *) echo "only files under ~/Downloads and ~/butler-drop are fetched, not $d" >&2; exit 4 ;;
esac
f="$d/$(basename "$p")"
printf '%%s\n' "$f"
wc -c < "$f" | tr -d ' '
"""
FOLDER = re.compile(r'^[a-z0-9]+(-[a-z0-9]+)*$')
DROP_NAME = re.compile(r'^[A-Za-z0-9][A-Za-z0-9._ ()+,-]{0,199}$')


def fetch(host, args):
    """Copies one file from host's ~/Downloads or ~/butler-drop into the index inbox's folder, through the drop spool."""
    if host not in DROP_HOSTS:
        raise Refused('fetch copies files from %s only, never from %s' % (' and '.join(DROP_HOSTS), host))
    if len(args) not in (2, 3):
        raise Refused('usage: mac <host> fetch <file> <inbox folder> [name]; a bare file name is in ~/Downloads')
    path, folder = args[0], args[1]
    if not FOLDER.match(folder):
        raise Refused('the inbox folder is one lowercase name, such as exports or messages, not %s' % folder)
    if system_of(host) == 'windows':
        raise Refused('fetch works on jimbo only while it runs Linux')
    take(host, 'fetch %s into %s' % (clip(redact(path), 200), folder), 'Copying %s to spike' % clip(os.path.basename(path), 60))
    result = remote(host, FETCH_RESOLVE % shlex.quote(path), timeout=25)
    lines = result.stdout.splitlines()
    if result.returncode != 0 or len(lines) != 2 or not lines[1].isdigit():
        raise Refused((result.stderr.strip() or 'could not read %s on %s' % (path, host)))
    source, size = lines[0], int(lines[1])
    if size > DROP_MAX:
        raise Refused('%s is %d MB, over the %d MB fetch limit' % (source, size >> 20, DROP_MAX >> 20))
    name = args[2] if len(args) == 3 else os.path.basename(source)
    if not DROP_NAME.match(name) or name.endswith('.partial'):
        name = re.sub(r'[^A-Za-z0-9._ ()+,-]', '_', name).lstrip('._ -')[:200] or 'file'
        if len(args) == 3:
            raise Refused('the name may hold letters, digits, spaces and . _ ( ) + , - only; try %s' % name)
    if folder == 'outbox':
        return fetch_to_outbox(host, source, size, name)
    partials, spool, results = (os.path.join(DROP, part) for part in ('partial', 'spool', 'results'))
    for folder_path in (partials, spool, results):
        os.makedirs(folder_path, mode=0o700, exist_ok=True)
    now = time.time()
    for old in os.listdir(partials):
        if now - os.path.getmtime(os.path.join(partials, old)) > 3600:
            os.unlink(os.path.join(partials, old))
    entry = '%s--%s' % (folder, name)
    partial = os.path.join(partials, '%d-%s' % (os.getpid(), name))
    answer = os.path.join(results, entry)
    try:
        os.unlink(answer)
    except FileNotFoundError:
        pass
    started = time.time()
    try:
        with open(partial, 'wb') as out:
            copied = subprocess.run(ssh_args(host) + ['cat -- %s' % shlex.quote(source)], stdin=subprocess.DEVNULL,
                                    stdout=out, stderr=subprocess.PIPE, timeout=900)
        got = os.path.getsize(partial)
        if copied.returncode != 0:
            raise Refused('copying %s failed: %s' % (source, copied.stderr.decode(errors='replace').strip() or 'exit %d' % copied.returncode))
        if got != size:
            raise Refused('%s changed while it was copied, %d bytes then %d; try again once it has finished downloading' % (source, size, got))
        os.rename(partial, os.path.join(spool, entry))
    except subprocess.TimeoutExpired:
        raise Refused('gave up copying %s after 15 minutes' % source)
    finally:
        if os.path.exists(partial):
            os.unlink(partial)
    audit([(host, 'fetched %s (%d bytes) into the index inbox %s as %s' % (clip(redact(source), 200), size, folder, name))])
    deadline = time.time() + 30
    while time.time() < deadline and not os.path.exists(answer):
        time.sleep(0.5)
    if not os.path.exists(answer):
        print('copied %s (%d bytes, %.0f s) to spike; the index inbox has not answered yet, so check again later' % (source, size, time.time() - started))
        return
    with open(answer) as handle:
        verdict = handle.read().strip()
    os.unlink(answer)
    if not verdict.startswith('ok'):
        raise Refused('the index inbox refused %s: %s' % (name, verdict.partition(' ')[2] or verdict))
    print('copied %s (%d bytes, %.0f s) into the index inbox as %s/%s; the ingest picks it up from there' % (source, size, time.time() - started, folder, name))


def fetch_to_outbox(host, source, size, name):
    """Copies a fetched file into butler's outbox instead of the index, so `asset add` can keep it in the asset store."""
    os.makedirs(OUTBOX, exist_ok=True)
    target = os.path.join(OUTBOX, 'fetched-%s' % name)
    partial = target + '.partial'
    try:
        with open(partial, 'wb') as out:
            copied = subprocess.run(ssh_args(host) + ['cat -- %s' % shlex.quote(source)], stdin=subprocess.DEVNULL,
                                    stdout=out, stderr=subprocess.PIPE, timeout=900)
        if copied.returncode != 0:
            raise Refused('copying %s failed: %s' % (source, copied.stderr.decode(errors='replace').strip() or 'exit %d' % copied.returncode))
        if os.path.getsize(partial) != size:
            raise Refused('%s changed while it was copied; try again once it has finished saving' % source)
        os.rename(partial, target)
    except subprocess.TimeoutExpired:
        raise Refused('gave up copying %s after 15 minutes' % source)
    finally:
        if os.path.exists(partial):
            os.unlink(partial)
    audit([(host, 'fetched %s (%d bytes) into the outbox as %s' % (clip(redact(source), 200), size, os.path.basename(target)))])
    print(target)


def push(host, args):
    """Copies one file butler may attach from spike to host's ~/butler-drop, or a folder in ~/Downloads."""
    if system_of(host) == 'windows':
        raise Refused('push works on jimbo only while it runs Linux')
    try:
        plan = push_check(args[0] if args else '', args[1:], os.environ, PUSH_ROOTS, PUSH_SENSITIVE_ROOTS, PUSH_SCRATCH, DROP_MAX)
    except PushRefused as error:
        raise Refused(str(error))
    name = os.path.basename(plan['path'])
    # A sensitive document's name is all the overlay and audit show; nothing reads its contents.
    take(host, 'push %s to %s' % (clip(redact(plan['path']), 200), host), 'Copying %s to this Mac' % clip(name, 60))

    def run_there(script, stdin_path):
        connect_ssh(host)
        stdin = open(stdin_path, 'rb') if stdin_path else subprocess.DEVNULL
        try:
            done = subprocess.run(ssh_args(host) + ['sh -c %s' % shlex.quote(script)], stdin=stdin, capture_output=True, timeout=900)
        finally:
            if stdin_path:
                stdin.close()
        return done.returncode, done.stdout.decode(errors='replace'), done.stderr.decode(errors='replace')

    try:
        placed = push_run(plan, host, run_there, PUSHED)
    except PushRefused as error:
        raise Refused(str(error))
    except subprocess.TimeoutExpired:
        raise Refused('gave up copying %s after 15 minutes' % plan['path'])
    lasts = ' It is deleted there in 30 minutes.' if plan['sensitive'] and not plan['keep'] else ''
    audit([(host, 'pushed %s%s (%d bytes) from spike to %s%s' % (
        'the sensitive document ' if plan['sensitive'] else '', clip(redact(plan['path']), 200), plan['size'], placed,
        ', kept' if plan['keep'] else ', deleted after 30 minutes' if plan['sensitive'] else ''))])
    print('copied %s (%d bytes) to %s on %s.%s' % (name, plan['size'], placed, host, lasts))


WINDOWS = r'''
echo "front: $(lsappinfo info -only name `lsappinfo front` | cut -d= -f2 | tr -d '"')"
echo "apps: $(lsappinfo visibleProcessList | grep -o '"[^"]*"' | tr -d '"' | paste -sd, - | sed 's/,/, /g')"
osascript -l JavaScript <<'EOF'
ObjC.import('CoreGraphics');
ObjC.import('AppKit');
var lines = [];
try {
  // Numbered as mac displays numbers them: the one with the menu bar first, then left to right, in points from the
  // menu bar display's top-left, where NSScreen counts from its bottom-left.
  var all = [], screens = $.NSScreen.screens, primary = screens.objectAtIndex(0).frame;
  for (var i = 0; i < screens.count; i++) {
    var s = screens.objectAtIndex(i), f = s.frame;
    all.push({ name: s.localizedName ? s.localizedName.js : '', x: f.origin.x, y: primary.size.height - f.origin.y - f.size.height, w: f.size.width, h: f.size.height, primary: i === 0 });
  }
  all.sort(function (a, b) { return a.primary ? -1 : b.primary ? 1 : (a.x - b.x) || (a.y - b.y); });
  all.forEach(function (s, i) {
    lines.push('screen ' + (i + 1) + ': ' + s.name + ', ' + s.w + 'x' + s.h + ' points at ' + s.x + ',' + s.y + (s.primary ? ', the main display, with the menu bar, which look shows' : ''));
  });
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


def expect_off(host, hours, reason):
    """Marks host expected off for the machines monitor, or clears the mark with hours None; never fails the command."""
    path = os.path.join(EXPECTED, host + '.json')
    try:
        if hours is None:
            os.unlink(path)
            return
        now = int(time.time())
        fd = os.open(path + '.tmp', os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NOFOLLOW, 0o660)
        with os.fdopen(fd, 'w') as f:
            json.dump({'host': host, 'until': now + int(hours * 3600), 'reason': reason, 'set': now, 'by': 'mac'}, f)
        os.replace(path + '.tmp', path)
    except OSError:
        pass


def keepawake(host, verb):
    if verb not in ('status', 'on', 'off', 'sleep'):
        raise Refused('keepawake takes status, on or off')
    if verb != 'status':
        journal(host, 'sleep' if verb == 'sleep' else 'keepawake ' + verb)
        if verb == 'on':
            expect_off(host, None, '')
        else:
            expect_off(host, 24 if verb == 'sleep' else 7 * 24, 'put to sleep by Butler' if verb == 'sleep' else 'keep-awake turned off by Butler')
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
        expect_off(host, 0.5, 'restarting into %s' % OS_NAMES[wanted])
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


# The Hammerspoon helper that jimbo's butler-access runs on each Mac, reached with curl over ssh on its loopback port,
# with the token only Aaron's account can read. It does what VNC cannot: menus and dialogs by name through the
# accessibility tree, every display, and moving windows between them, under Hammerspoon's own permissions.
HELPER = ('/usr/bin/curl -sS --max-time %d -H @"$HOME/.local/state/butler-access/hammerspoon-token" '
          '-H "Content-Type: application/json" --data-binary @- http://127.0.0.1:' + HELPER_PORT + '/')
HELPER_DOWN = ('Hammerspoon, butler\'s helper on %s, is not answering: it is not installed yet (Aaron runs just in jimbo on '
               'that Mac), not running (open -a Hammerspoon), or has not loaded butler\'s config (Aaron quits and reopens it)')


def helper(host, verb, args=None, timeout=45):
    if system_of(host) != 'macos':
        raise Refused('%s works only on the Macs' % verb)
    connect_ssh(host)
    try:
        result = subprocess.run(ssh_args(host) + [HELPER % (timeout - 5)], input=json.dumps({'verb': verb, 'args': args or {}}),
                                capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        raise Refused('the helper on %s did not answer within %d s' % (host, timeout))
    if result.returncode == 7:
        raise Refused(HELPER_DOWN % host)
    if result.returncode == 26:
        raise Refused('%s has no helper token yet: Aaron runs just in jimbo on that Mac' % host)
    if result.returncode != 0:
        raise Refused('the helper on %s failed: %s' % (host, ' '.join(result.stderr.split()) or 'curl exit %d' % result.returncode))
    try:
        reply = json.loads(result.stdout)
    except ValueError:
        raise Refused('the helper on %s answered something other than JSON: %s' % (host, result.stdout[:200]))
    if not reply.get('ok'):
        why = reply.get('error') or 'no reason given'
        if why == 'forbidden':
            why = 'the helper refused the token; Aaron quits and reopens Hammerspoon on %s' % host
        raise Refused(why)
    return reply['result']


def after(host, wait=0.6):
    """A screenshot of the main display once an action through the helper has had a moment to show."""
    time.sleep(wait)
    return ask(host, {'verb': 'look', 'args': [], 'stdin': ''})


def menu(host, args):
    if not args:
        raise Refused('menu takes an app, or front, then optionally a menu and an item, such as menu Bitwarden File "Export vault"')
    if args[1:]:
        journal(host, 'menu ' + ' > '.join(args))
    result = helper(host, 'menu', {'app': args[0], 'path': args[1:]})
    print(result)
    return result.startswith('chose ')


def press_or_focus(host, verb, args):
    if not args or len(args) > 2:
        raise Refused('%s takes a control\'s number or name from dialog, then optionally the app' % verb)
    journal(host, '%s %s' % (verb, ' '.join(args)))
    print(helper(host, verb, {'control': args[0], 'app': args[1] if len(args) > 1 else 'front'}))


def picture_size(display):
    width = min(SHOT_WIDTH, int(display['w'] * display.get('scale', 1)))
    return width, round(display['h'] * width / display['w'])


def displays(host):
    found = helper(host, 'displays')
    print('displays, numbered as display takes them, in points from the main display\'s top-left:')
    for display in found:
        width, height = picture_size(display)
        notes = []
        if display.get('primary'):
            notes.append('main, with the menu bar, which look and every other action show')
        if display.get('builtin'):
            notes.append('the built-in screen')
        print('  %d: %s, %dx%d points at %d,%d, scale %s, pictured %dx%d%s' % (
            display['index'], display['name'], display['w'], display['h'], display['x'], display['y'],
            display.get('scale', 1), width, height, ', ' + ', '.join(notes) if notes else ''))
    return found


def display_look(host, number):
    shot = helper(host, 'snapshot', {'display': number})
    path = outbox_picture(host, '-display%d' % shot['index'])
    with open(path, 'wb') as out:
        out.write(base64.b64decode(shot['png']))
    from PIL import Image
    with Image.open(path) as image:
        width, height = image.size
    return '%s (%dx%d, display %d, %s; x and y for display %d click are pixels of this picture)' % (
        path, width, height, shot['index'], shot['name'], shot['index'])


def display(host, args):
    if not args or not args[0].isdigit():
        raise Refused('display takes a number from displays, then look, or click <x> <y> [left|right|double]')
    number, verb, rest = int(args[0]), args[1] if len(args) > 1 else 'look', args[2:]
    if verb == 'look':
        print(display_look(host, number))
        return
    if verb != 'click' or len(rest) < 2 or not all(arg.isdigit() for arg in rest[:2]) or rest[2:] not in ([], ['left'], ['right'], ['double']):
        raise Refused('display <n> click takes <x> <y> [left|right|double], pixels of that display\'s picture')
    found = {entry['index']: entry for entry in helper(host, 'displays')}
    if number not in found:
        raise Refused('there is no display %d; this Mac has %d' % (number, len(found)))
    screen = found[number]
    width, height = picture_size(screen)
    x, y = int(rest[0]), int(rest[1])
    if x >= width or y >= height:
        raise Refused('%d,%d is outside display %d\'s %dx%d picture' % (x, y, number, width, height))
    point = {'x': screen['x'] + x * screen['w'] / width, 'y': screen['y'] + y * screen['h'] / height,
             'button': rest[2] if len(rest) > 2 else 'left'}
    journal(host, 'display %d click %s' % (number, ' '.join(rest)))
    helper(host, 'click', point)
    time.sleep(0.6)
    print(display_look(host, number))


def window(host, args):
    if args[:1] == ['display'] and len(args) == 2 and args[1].isdigit():
        journal(host, 'window display ' + args[1])
        print(helper(host, 'move_window', {'display': int(args[1])}))
    elif len(args) == 1 and args[0] in RECTANGLE_ACTIONS:
        if system_of(host) != 'macos':
            raise Refused('window works only on the Macs')
        journal(host, 'window ' + args[0])
        result = remote(host, "open -g 'rectangle://execute-action?name=%s'" % args[0], timeout=15)
        if result.returncode != 0:
            raise Refused('Rectangle did not take %s on %s: %s' % (args[0], host, result.stderr.strip() or 'exit %d' % result.returncode))
        print('Rectangle: %s on the front window' % args[0])
    else:
        raise Refused('window takes display <n>, or one of Rectangle\'s actions: ' + ', '.join(RECTANGLE_ACTIONS))
    print(after(host, 0.5))


def guard_password(host):
    """Refuses to type while the keyboard focus is in a password field or macOS's own password prompt."""
    try:
        state = helper(host, 'secure', timeout=15)
    except Refused:
        return
    if state.get('secure'):
        raise Refused('the keyboard focus on %s is in a password field or macOS\'s password prompt: Aaron types it himself, never you' % host)


# Outcome check: approval is for what an action does, not for the Mac. Where the front window is a messaging, mail or
# payment context, pressing Return, typing a newline, clicking or pressing a control may send, post or pay, so mac
# refuses it until butler states the outcome with `mac <host> confirm "<what will happen>" <action...>`, which the
# daemon always asks Aaron for, showing that statement. It reads only the front app and its window's title or URL, so
# it misses a send it cannot see there, and an unreadable front window lets the action through.
# Under a mission Aaron approved, the daemon names in BUTLER_MISSION_KINDS the outcome kinds it lists on this machine,
# and a messaging or mail window lets the action through when it lists sends or publishing there, since Aaron asked on
# 4 Nov 2026 for one approval per run. A payment, checkout or bank page still wants `confirm`, which asks him nothing
# under such a mission but is how the daemon checks the payee and amount against the mission's cap.
MESSAGING_APPS = re.compile(r'(?i)^(?:messages|mail|slack|discord|whatsapp|messenger|signal|telegram|microsoft outlook|outlook|microsoft teams|teams|spark|airmail|mimestream|superhuman|thunderbird|facetime)\b')
PAYING_APPS = re.compile(r'(?i)^(?:paypal|wallet)\b')
BROWSERS = re.compile(r'(?i)chrom|safari|firefox|arc\b|brave|edge|orion|vivaldi|opera|cmux|webkit')
SENDING_PAGES = re.compile(r'(?i)\b(?:gmail|inbox|outlook|mail|messenger|messages|whatsapp|slack|discord|facebook|instagram|linkedin|twitter|compose|reply|sign up)\b')
PAYING_PAGES = re.compile(r'(?i)\b(?:checkout|check out|payment|pay|paypal|cart|basket|order|billing|purchase|subscribe|subscription|bank|banking|netbank|commbank|westpac|anz|nab|stripe|afterpay|transfer|booking|book now|reservation)\b')
MISSION_SENDS = {'message', 'publish', 'confirm', 'signup'}
LINUX_FRONT = LINUX_ENV + 'hyprctl activewindow -j 2> /dev/null'
CONFIRMED = []


def mission_kinds():
    """The outcome kinds the thread's mission lists on this call's machine, as the daemon passes them."""
    return set(filter(None, os.environ.get('BUTLER_MISSION_KINDS', '').split(',')))


def front_context(host):
    """The front app and window title or URL, or None when they cannot be read."""
    system = system_of(host)
    try:
        if system == 'macos':
            try:
                found = helper(host, 'front', timeout=15)
                return found.get('app', ''), ' '.join(filter(None, [found.get('title', ''), found.get('url', '')]))
            except Refused:
                lines = remote(host, 'lsappinfo info -only name `lsappinfo front`', timeout=10).stdout.splitlines()
                return (lines[0].split('=', 1)[-1].strip().strip('"') if lines else ''), ''
        if system == 'linux':
            found = json.loads(remote(host, LINUX_FRONT, timeout=10).stdout or '{}')
            return found.get('class', ''), found.get('title', '')
    except (Refused, subprocess.TimeoutExpired, ValueError):
        return None
    return None


def committing(verb, args, stdin):
    """Whether an action could send, post or pay in the window it lands in."""
    if verb in ('click', 'press'):
        return True
    if verb == 'display':
        return args[1:2] == ['click']
    if verb == 'menu':
        return len(args) > 1
    if verb == 'key':
        return any(keys(combo).split('-')[-1] == 'enter' for combo in args)
    if verb == 'type':
        return '\n' in (' '.join(args) if args else stdin)
    return False


def guard_outcome(host, verb, args, stdin=''):
    """Refuses an action that may send, post or pay in a messaging, mail or payment window until it is confirmed."""
    if CONFIRMED or not committing(verb, args, stdin):
        return
    context = front_context(host)
    if not context:
        return
    app, title = context
    browser = BROWSERS.search(app or '')
    paying = PAYING_APPS.search(app or '') or (browser and PAYING_PAGES.search(title or ''))
    sending = MESSAGING_APPS.search(app or '') or (browser and SENDING_PAGES.search(title or ''))
    if not sending and not paying:
        return
    if sending and not paying and mission_kinds() & MISSION_SENDS:
        return
    where = '%s%s' % (app, ', "%s"' % clip(title, 80) if title else '')
    raise Refused('outcome check: the front window on %s is %s, where this %s may send, post or pay something. Tell Aaron exactly what will happen, then run it again as: mac %s confirm "<what will happen, such as: send \'on my way\' to Rylee in Messages>" %s' % (
        host, where, verb, host, ' '.join([verb] + [shlex.quote(arg) for arg in args])))


# Control sessions: from the first command that uses a machine's screen or shell until `mac <host> done`, its
# connection closing, or CONTROL_IDLE seconds without a command, the last of which also covers a turn that ended,
# crashed or was cut short by a restart of butler, since nothing tells mac a turn is over. On a Mac, Butler sits at
# the top right of the screen all that time, through the butler-overlay command jimbo's butler-access module installs,
# with up to three speech bubbles: butler's own words from `say`, or a terse note of what an action does when he has
# said nothing lately. Every action and bubble goes to the audit trail in butler's memory, `audit/mac/YYYY-MM-DD.md`,
# through memory-audit, which butler cannot edit. The overlay protocol, show, say, act and hide, names no platform, so
# jimbo can gain one later; for now only the Macs have it.

SECRET_WORD = re.compile(r'(?i)\b(pass(?:word|wd|phrase|code)?|pin|otp|secret|token|api[_-]?key|auth(?:orization)?|bearer|cookie|credentials?)\b(\s*[:=]\s*|\s+)(\S+)')


def redact(text):
    """Text as one line, with anything that looks like a secret cut out, for a bubble or the audit trail."""
    text = SECRET_WORD.sub(lambda match: match.group(1) + match.group(2) + '[redacted]', ' '.join(text.split()))
    words = []
    for word in text.split(' '):
        bare = word.strip('"\',;()[]{}')
        looks_like_key = re.fullmatch(r'[A-Za-z0-9+/_=.-]+', bare) and re.search(r'\d', bare) and re.search(r'[A-Za-z]', bare)
        if len(bare) >= 24 and not bare.startswith(('/', '~', '.', 'http')) and looks_like_key:
            word = word.replace(bare, '[redacted]')
        words.append(word)
    return ' '.join(words)


def clip(text, limit):
    return text if len(text) <= limit else text[:limit - 1].rstrip() + '…'


def command_name(words, stdin):
    command = ' '.join(words) if words else stdin
    first = command.split()[0] if command.split() else 'a script'
    return clip(redact(os.path.basename(first)), 40)


def describe(verb, args, stdin):
    """What an action did, for the audit trail; never what was typed, and a shell command only with secrets cut."""
    if verb == 'type':
        return 'type (%d characters, not logged)' % len(' '.join(args) if args else stdin)
    if verb == 'run':
        command = ' '.join(args) if args else stdin
        return 'run: ' + clip(redact(command), 300)
    return ' '.join([verb] + list(args))


def narrate(verb, args, stdin):
    """A terse, honest bubble for an action, or None; never the text typed or a whole script."""
    if verb == 'look':
        return None
    if verb == 'click':
        how = args[2] if len(args) > 2 else 'left'
        return '%s at %s, %s' % ({'left': 'Clicking', 'double': 'Double-clicking', 'right': 'Right-clicking', 'middle': 'Middle-clicking'}[how], args[0], args[1])
    if verb == 'move':
        return 'Moving the pointer'
    if verb == 'drag':
        return 'Dragging from %s, %s to %s, %s' % tuple(args[:4])
    if verb == 'scroll':
        return 'Scrolling %s' % args[2]
    if verb == 'type':
        return 'Typing…'
    if verb == 'key':
        return 'Pressing ' + ', '.join(args)
    if verb == 'windows':
        return 'Checking the open windows'
    if verb == 'run':
        return 'Running %s' % command_name(args, stdin)
    if verb == 'record':
        return 'Recording the screen' if args[:1] == ['start'] else 'Stopping the recording'
    return None


def control_file(host):
    return os.path.join(CONTROL, host + '.json')


class Locked:
    def __enter__(self):
        os.makedirs(CONTROL, exist_ok=True)
        self.file = open(os.path.join(CONTROL, 'lock'), 'w')
        fcntl.flock(self.file, fcntl.LOCK_EX)

    def __exit__(self, *_):
        self.file.close()


def load(host):
    try:
        with open(control_file(host)) as state:
            return json.load(state)
    except (FileNotFoundError, ValueError):
        return None


def save(host, state):
    with open(control_file(host) + '.new', 'w') as out:
        json.dump(state, out)
    os.replace(control_file(host) + '.new', control_file(host))


def thread_tag():
    """The thread running this command, from the daemon's BUTLER_THREAD_ID and BUTLER_THREAD_TITLE, so two threads on one
    machine can be told apart in the audit trail; empty outside a thread, such as for the idle watcher of an older daemon."""
    ident = re.sub(r'[^0-9A-Za-z_-]', '', os.environ.get('BUTLER_THREAD_ID', ''))[:32]
    if not ident:
        return ''
    title = clip(redact(os.environ.get('BUTLER_THREAD_TITLE', '')).replace('"', "'"), 60)
    return '[thread %s%s] ' % (ident, ' "%s"' % title if title else '')


def audit(lines):
    """Spools lines for audit/mac in butler's memory, then has memory-audit commit them in the background."""
    if not lines:
        return
    os.makedirs(STATE, exist_ok=True)
    day, clock = time.strftime('%Y-%m-%d'), time.strftime('%H:%M:%S %z')
    tag = thread_tag()
    with open(AUDIT_SPOOL, 'a') as spool:
        fcntl.flock(spool, fcntl.LOCK_EX)
        for host, text in lines:
            spool.write('%s\t%s %s %s%s\n' % (day, clock, host, tag, ' '.join(text.split())))
    try:
        subprocess.Popen([MEMORY_AUDIT, 'mac', AUDIT_SPOOL], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL, start_new_session=True)
    except OSError:
        pass


def overlay(host, verb, text=''):
    """Tells the Mac's overlay to show Butler, show a bubble or hide; quietly nothing on a Mac not switched to it yet."""
    if HOSTS[host].get('os') != 'macos':
        return False
    try:
        result = remote(host, '%s %s %s' % (OVERLAY, verb, shlex.quote(text)), timeout=10)
    except subprocess.TimeoutExpired:
        return False
    return result.returncode == 0


def sweep(lines, now):
    """Ends every control session that went quiet, such as one a restart of butler cut off before its watcher ran."""
    try:
        names = os.listdir(CONTROL)
    except FileNotFoundError:
        return
    for name in names:
        if name.endswith('.json') and name[:-5] in HOSTS:
            state = load(name[:-5])
            if state and now - state['last'] > CONTROL_IDLE:
                os.remove(control_file(name[:-5]))
                lines.append((name[:-5], 'end of control (idle timeout), %d s' % (state['last'] - state['started'])))


def take(host, what, bubble=None, spoken=False, opening=None):
    """Records one command in host's control session, starting one when none is live, and shows it on the overlay."""
    lines = []
    now = time.time()
    with Locked():
        sweep(lines, now)
        state = load(host)
        starting = state is None
        if starting:
            state = {'id': '%d-%d' % (now * 1000, os.getpid()), 'started': now, 'said': 0, 'auto': '', 'autoAt': 0}
            lines.append((host, 'start of control'))
            bubble = bubble or opening
        state['last'] = now
        shown = None
        if spoken:
            shown = bubble
            state['said'] = now
        elif bubble and now - state['said'] > QUIET_AFTER_SAY and not (bubble == state['auto'] and now - state['autoAt'] < QUIET_AFTER_SAY):
            shown = bubble
            state['auto'], state['autoAt'] = bubble, now
        lines.append((host, what + (' | bubble: "%s"' % shown if shown else '')))
        save(host, state)
    audit(lines)
    if starting:
        subprocess.Popen([sys.argv[0], host, 'watch', state['id']], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL, start_new_session=True)
    return overlay(host, 'say' if spoken else 'act' if shown else 'show', shown or '')


def end(host, reason, session=None, idle_only=False, hide=True):
    """Ends host's control session, if one is live, and fades the overlay out."""
    with Locked():
        state = load(host)
        if state is None or (session and state['id'] != session):
            return False
        if idle_only and time.time() - state['last'] <= CONTROL_IDLE:
            return False
        os.remove(control_file(host))
    audit([(host, 'end of control (%s), %d s' % (reason, time.time() - state['started']))])
    if hide:
        try:
            overlay(host, 'hide')
        except Refused:
            pass
    return True


def watch(host, session):
    """Waits beside a control session, and ends it once it has been idle for CONTROL_IDLE seconds."""
    while True:
        state = load(host)
        if state is None or state['id'] != session:
            return
        wait = state['last'] + CONTROL_IDLE - time.time()
        if wait < 0 and end(host, 'idle timeout', session=session, idle_only=True):
            return
        time.sleep(max(wait, 0) + 1)


def say(host, words):
    text = clip(redact(' '.join(words) if words else sys.stdin.read()), SAY_LIMIT)
    if not text:
        raise Refused('say takes what to say, as args or on stdin')
    if take(host, 'say', text, spoken=True):
        print('said on %s: "%s"' % (host, text))
    elif HOSTS[host].get('os') == 'macos':
        print('logged, but %s showed no bubble: it has no butler-overlay until Aaron switches it to jimbo' % host)
    else:
        print('logged; %s has no overlay yet, so nothing was shown' % host)


def done(host, words):
    """Ends the control session; a note after done, or on stdin, is what was left open, kept in the audit trail, and the
    daemon's thread ledger shows it to the next thread that drives this machine."""
    note = clip(redact(' '.join(words) if words else ('' if sys.stdin.isatty() else sys.stdin.read())), 200)
    if note:
        audit([(host, 'left open: ' + note)])
    if end(host, 'done'):
        print('handed %s back to Aaron; Butler has left its screen%s' % (host, '; left open: ' + note if note else ''))
        return
    try:
        overlay(host, 'hide')
    except Refused:
        pass
    print('was not in control of %s; hid its overlay anyway' % host)


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
    if verb == 'serve':
        return serve(host)
    if verb == 'watch':
        return watch(host, rest[0])
    if verb == 'record' and rest[:1] == ['loop']:
        return record(host, 'loop')
    try:
        result = act_on(host, verb, rest)
        if verb not in NO_PRESENCE:
            presence(host, verb, rest)
        return result
    except Lost as error:
        end(host, 'connection closed: %s' % clip(str(error), 120), hide=False)
        raise


# Verbs that look at or act on no screen, so they add no presence note.
NO_PRESENCE = {'say', 'done', 'fetch', 'push', 'keepawake', 'sleep', 'boot', 'record', 'serve', 'watch'}


def presence(host, verb, rest):
    """Records what this thread now sees in front on host, and prints who else used it lately and whether Aaron is at it.
    Advice only: it never refuses, and a failure to read the machine says nothing."""
    try:
        now = time.time()
        me = re.sub(r'[^0-9A-Za-z_-]', '', os.environ.get('BUTLER_THREAD_ID', ''))[:32]
        front = front_context(host) or ('', '')
        idle = None
        if system_of(host) == 'macos':
            out = remote(host, MACOS_IDLE, timeout=10).stdout.strip()
            idle = int(out) if out.isdigit() else None
        before = presence_load(PRESENCE, host)
        last_butler = presence_last_butler(before, now)
        state = load(host)
        if state:
            last_butler = max(last_butler, state.get('last', 0))
        entry = {
            'session': clip(redact(os.environ.get('BUTLER_DESK_SESSION', '')), 50),
            'title': clip(redact(os.environ.get('BUTLER_THREAD_TITLE', '')), 60),
            'app': clip(front[0], 40),
            'window': clip(redact(front[1]), 60),
            'action': clip(describe(verb, rest, ''), 60),
        }
        data = presence_record(PRESENCE, host, me, entry, now)
        note = presence_note(presence_lines(data, me, host, now), aaron_active(idle, last_butler, now), idle, host)
        if note:
            print(note)
    except (Refused, Lost, subprocess.TimeoutExpired, OSError, ValueError):
        pass


def act_on(host, verb, rest):
    if verb == 'confirm':
        if len(rest) < 2 or rest[1] == 'confirm':
            raise Refused('confirm takes what will happen, in quotes, then the action, such as confirm "send \'on my way\' to Rylee in Messages" key enter')
        audit([(host, 'confirmed outcome, approved by Aaron: %s | %s' % (clip(redact(rest[0]), 200), describe(rest[1], rest[2:], '')))])
        CONFIRMED.append(rest[0])
        return act_on(host, rest[1], rest[2:])
    if verb == 'say':
        return say(host, rest)
    if verb == 'done':
        return done(host, rest)
    if verb == 'run':
        stdin = '' if rest else sys.stdin.read()
        journal(host, describe('run', rest, stdin))
        take(host, describe('run', rest, stdin), narrate('run', rest, stdin))
        return run(host, rest, stdin)
    if verb == 'fetch':
        return fetch(host, rest)
    if verb == 'push':
        return push(host, rest)
    if verb == 'windows':
        take(host, 'windows', narrate('windows', rest, ''))
        return windows(host)
    if verb == 'record':
        if rest[:1] in (['start'], ['stop']):
            take(host, 'record ' + rest[0], narrate('record', rest, ''))
        return record(host, rest[0] if rest else '')
    if verb == 'keepawake':
        if rest[:1] in (['on'], ['off']):
            audit([(host, 'keepawake ' + rest[0])])
        return keepawake(host, rest[0] if rest else 'status')
    if verb == 'sleep':
        audit([(host, 'sleep')])
        return keepawake(host, 'sleep')
    if verb == 'boot':
        if rest[1:] == ['confirm']:
            audit([(host, 'boot ' + ' '.join(rest))])
        return boot(host, rest)
    if verb == 'menu':
        guard_outcome(host, verb, rest)
        take(host, 'menu ' + ' > '.join(rest), clip(redact('Choosing ' + ' > '.join(rest[1:]) if rest[1:] else 'Reading the menus of ' + ' '.join(rest[:1])), 80))
        if menu(host, rest):
            print(after(host))
        return
    if verb == 'dialog':
        take(host, 'dialog ' + ' '.join(rest), 'Reading the dialog')
        print(helper(host, 'dialog', {'app': rest[0] if rest else 'front'}))
        return
    if verb in ('press', 'focus'):
        guard_outcome(host, verb, rest)
        take(host, '%s %s' % (verb, redact(' '.join(rest))), '%s %s' % ('Pressing' if verb == 'press' else 'Moving to', clip(redact(' '.join(rest[:1])), 60)))
        press_or_focus(host, verb, rest)
        if verb == 'press':
            print(after(host))
        return
    if verb == 'displays':
        take(host, 'displays', 'Checking the displays')
        displays(host)
        return
    if verb == 'display':
        guard_outcome(host, verb, rest)
        clicking = rest[1:2] == ['click']
        take(host, 'display ' + ' '.join(rest), 'Clicking on display %s' % rest[0] if clicking and rest else None)
        return display(host, rest)
    if verb == 'window':
        take(host, 'window ' + ' '.join(rest), 'Arranging the window')
        return window(host, rest)
    if verb not in ACTIONS:
        print(USAGE, file=sys.stderr)
        return 2
    check(verb, rest, system_of(host) if verb == 'key' else 'macos')
    stdin = sys.stdin.read() if verb == 'type' and not rest else ''
    wide = sorted({character for character in ' '.join(rest) + stdin if ord(character) > 0xFF})
    if wide:
        raise Refused('type sends Latin-1 only, not %s; on a Mac run pbcopy with the text on stdin, then key cmd-v; on Linux run wl-copy with it, then key ctrl-v' % ' '.join(wide))
    if verb == 'type' and system_of(host) == 'macos':
        guard_password(host)
    guard_outcome(host, verb, rest, stdin)
    take(host, describe(verb, rest, stdin), narrate(verb, rest, stdin), opening='Taking a look at the screen')
    print(ask(host, {'verb': verb, 'args': rest, 'stdin': stdin}))


if __name__ == '__main__':
    try:
        sys.exit(main())
    except Refused as error:
        print('mac: %s' % error, file=sys.stderr)
        sys.exit(75)
