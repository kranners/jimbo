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
SETTLE = 0.6
RECORD_INTERVAL = 0.5
RECORD_LIMIT = 15 * 60
IDLE = 600
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


def look(host, client):
    client.refreshScreen(incremental=True)
    image = picture(client)
    shots = os.path.join(RUNTIME, 'shots')
    os.makedirs(shots, exist_ok=True)
    for old in os.listdir(shots):
        if os.path.getmtime(os.path.join(shots, old)) < time.time() - 3600:
            os.remove(os.path.join(shots, old))
    path = os.path.join(shots, '%s-%s.png' % (host, time.strftime('%H%M%S')))
    image.save(path, compress_level=1)
    return '%s (%dx%d, read it to see the screen)' % (path, image.width, image.height)


def keys(combo):
    return '-'.join(ALIASES.get(part.lower(), part) for part in combo.split('-'))


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
        client.mouseMove(*point(client, args[0], args[1]))
        client.mouseDown(1)
        client.mouseDrag(*point(client, args[2], args[3]), step=20)
        client.mouseUp(1)
    elif verb == 'scroll':
        client.mouseMove(*point(client, args[0], args[1]))
        button = 4 if args[2] == 'up' else 5
        for _ in range(int(args[3]) if len(args) > 3 else 3):
            client.mousePress(button)
    elif verb == 'type':
        text = ' '.join(args) if args else stdin
        for character in text:
            client.keyPress(TYPED.get(character, character))
    elif verb == 'key':
        for combo in args:
            client.keyPress(keys(combo))
    return '%s %s' % (verb, ' '.join(args)) if args else verb


ACTIONS = ('look', 'click', 'move', 'drag', 'scroll', 'type', 'key')


def session(host):
    return os.path.join(RUNTIME, host + '.session')


def serve(host):
    client = screen(host)

    class Handler(socketserver.StreamRequestHandler):
        def handle(self):
            request = json.loads(self.rfile.readline())
            try:
                if request['verb'] != 'look':
                    journal(host, act(client, request['verb'], request['args'], request['stdin']))
                    time.sleep(SETTLE)
                reply = {'ok': True, 'text': look(host, client)}
            except Exception as error:
                reply = {'ok': False, 'text': '%s: %s' % (type(error).__name__, error)}
            self.wfile.write(json.dumps(reply).encode() + b'\n')
            self.server.done = not reply['ok']

    class Server(socketserver.UnixStreamServer):
        timeout = IDLE
        done = False

        def handle_timeout(self):
            self.done = True

    path = session(host)
    if os.path.exists(path):
        os.remove(path)
    server = Server(path, Handler)
    try:
        while not server.done:
            server.handle_request()
    finally:
        os.remove(path)
        client.disconnect()
        from vncdotool import api
        api.shutdown()


def ask(host, request, retry=True):
    path = session(host)
    if not os.path.exists(path):
        os.makedirs(RUNTIME, mode=0o700, exist_ok=True)
        log = open(os.path.join(RUNTIME, host + '.log'), 'w')
        subprocess.Popen([sys.argv[0], host, 'serve'], stdin=subprocess.DEVNULL, stdout=log, stderr=log, start_new_session=True)
        deadline = time.time() + 40
        while not os.path.exists(path):
            if time.time() > deadline:
                with open(os.path.join(RUNTIME, host + '.log')) as failed:
                    raise Refused('could not reach %s screen: %s' % (host, failed.read().strip().splitlines()[-1:] or 'timed out'))
            time.sleep(0.2)
    try:
        with socket.socket(socket.AF_UNIX) as connection:
            connection.settimeout(50)
            connection.connect(path)
            connection.sendall(json.dumps(request).encode() + b'\n')
            reply = json.loads(connection.makefile().readline())
    except (ConnectionError, FileNotFoundError, json.JSONDecodeError):
        if not retry:
            raise
        if os.path.exists(path):
            os.remove(path)
        return ask(host, request, retry=False)
    if not reply['ok']:
        if retry:
            return ask(host, request, retry=False)
        raise Refused(reply['text'])
    return reply['text']


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
    result = remote(host, ' '.join(words) if words else sys.stdin.read())
    print(result.stdout, end='')
    if result.stderr:
        print('[stderr]\n' + result.stderr, end='')
    print('[exit %d]' % result.returncode)


def recording(host):
    return os.path.join(RUNTIME, 'record-' + host)


def record(host, verb):
    folder = recording(host)
    if verb == 'start':
        if os.path.exists(os.path.join(folder, 'pid')):
            raise Refused('already recording %s; mac %s record stop first' % (host, host))
        os.makedirs(os.path.join(folder, 'frames'), exist_ok=True)
        subprocess.Popen(
            [sys.argv[0], host, 'record', 'loop'], stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL, stderr=open(os.path.join(folder, 'log'), 'w'),
            start_new_session=True,
        )
        print('recording %s, at most %d minutes; mac %s record stop to get the video' % (host, RECORD_LIMIT // 60, host))
    elif verb == 'stop':
        if not os.path.exists(os.path.join(folder, 'pid')):
            raise Refused('not recording %s' % host)
        open(os.path.join(folder, 'stop'), 'w').close()
        deadline = time.time() + 55
        while os.path.exists(os.path.join(folder, 'pid')) and time.time() < deadline:
            time.sleep(0.5)
        with open(os.path.join(folder, 'log')) as log:
            print(log.read().strip().splitlines()[-1])
    elif verb == 'loop':
        record_loop(host, folder)


def record_loop(host, folder):
    with open(os.path.join(folder, 'pid'), 'w') as pid:
        pid.write(str(os.getpid()))
    frames = os.path.join(folder, 'frames')
    stamps = []
    try:
        client = screen(host)
        started = time.time()
        while not os.path.exists(os.path.join(folder, 'stop')) and time.time() - started < RECORD_LIMIT:
            client.refreshScreen(incremental=True)
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
             '-vf', 'fps=10', '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '28',
             '-pix_fmt', 'yuv420p', '-movflags', '+faststart', video],
            check=True,
        )
        journal(host, 'recorded %s' % video)
        print('saved %s, %d s, attach it with attach_file' % (video, round(stamps[-1] - stamps[0])), file=sys.stderr)
    finally:
        for name in os.listdir(frames):
            os.remove(os.path.join(frames, name))
        for name in ('pid', 'stop'):
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
    print(ask(host, {'verb': verb, 'args': rest, 'stdin': '' if rest or verb != 'type' else sys.stdin.read()}))


if __name__ == '__main__':
    try:
        sys.exit(main())
    except Refused as error:
        print('mac: %s' % error, file=sys.stderr)
        sys.exit(75)
