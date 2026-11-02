import json
import os
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
SHOT_WIDTH = 1512
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
       mac <host> run [shell words]    (script on stdin when no arg)
       mac <host> record start | stop
x and y are pixels of the last picture from look, whose top-left is 0 0.'''


class Refused(Exception):
    pass


def ssh_args(host, *options):
    target = HOSTS[host]
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


def remote(host, command, timeout=50):
    connect_ssh(host)
    return subprocess.run(
        ssh_args(host) + [command], stdin=subprocess.DEVNULL,
        capture_output=True, text=True, timeout=timeout,
    )


def tunnel(host):
    connect_ssh(host)
    path = os.path.join(RUNTIME, host + '.vnc')
    forward = '%s:127.0.0.1:5900' % path
    control_forward = subprocess.run(ssh_args(host, '-O', 'forward', '-L', forward), capture_output=True, text=True)
    if control_forward.returncode != 0 and 'already' not in control_forward.stderr:
        raise Refused('could not tunnel to %s screen sharing: %s' % (host, control_forward.stderr.strip()))
    return path


def screen(host):
    path = tunnel(host)
    password = remote(host, 'cat ' + PASSWORD)
    if password.returncode != 0:
        raise Refused('%s has no VNC password yet; switch it to jimbo with butler-access' % host)
    from vncdotool import api, client as vnc, rfb
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
    client = api.connect(path, password=password.stdout.strip(), timeout=20)
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
    shots = os.path.join(RUNTIME, 'shots')
    os.makedirs(shots, exist_ok=True)
    for old in os.listdir(shots):
        if os.path.getmtime(os.path.join(shots, old)) < time.time() - 3600:
            os.remove(os.path.join(shots, old))
    path = os.path.join(shots, '%s-%s-%03d.png' % (host, time.strftime('%H%M%S'), time.time() * 1000 % 1000))
    image.save(path, compress_level=1)
    return '%s (%dx%d, read it to see the screen)' % (path, image.width, image.height)


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


def check(verb, args):
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


def hosts():
    for host, target in HOSTS.items():
        try:
            state = remote(host, 'ioreg -n Root -d1 | grep -c "CGSSessionScreenIsLocked\\"=Yes"; lsappinfo info -only name `lsappinfo front`', timeout=15)
            lines = state.stdout.splitlines()
            locked = lines[0].strip() != '0' if lines else False
            front = lines[1].split('=', 1)[-1].strip('"') if len(lines) > 1 else 'unknown'
            print('%s (%s): up, %s, front app %s' % (host, target['address'], 'LOCKED' if locked else 'unlocked', front))
        except (Refused, subprocess.TimeoutExpired) as error:
            print('%s (%s): down, %s' % (host, target['address'], error))


def run(host, words):
    try:
        result = remote(host, ' '.join(words) if words else sys.stdin.read())
    except subprocess.TimeoutExpired:
        raise Refused('gave up after 50 s; the command may still be running on %s, so background anything long with its output redirected to a file' % host)
    print(result.stdout, end='')
    if result.stderr:
        print('[stderr]\n' + result.stderr, end='')
    print('[exit %d]' % result.returncode)


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
    if verb == 'record':
        return record(host, rest[0] if rest else '')
    if verb == 'serve':
        return serve(host)
    if verb not in ACTIONS:
        print(USAGE, file=sys.stderr)
        return 2
    check(verb, rest)
    stdin = sys.stdin.read() if verb == 'type' and not rest else ''
    wide = sorted({character for character in ' '.join(rest) + stdin if ord(character) > 0xFF})
    if wide:
        raise Refused('type sends Latin-1 only, not %s; run pbcopy with the text on stdin, then key cmd-v' % ' '.join(wide))
    print(ask(host, {'verb': verb, 'args': rest, 'stdin': stdin}))


if __name__ == '__main__':
    try:
        sys.exit(main())
    except Refused as error:
        print('mac: %s' % error, file=sys.stderr)
        sys.exit(75)
