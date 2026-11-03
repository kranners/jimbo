"""remote-desk: Aaron's own web remote desktop on spike, for his iPad.

It serves a launcher and a noVNC viewer behind Caddy, which lets a request through only once spike's device gate has
signed the device in, naming its WireGuard peer in X-Device-Gate-Device, and opens each screen through a fresh ssh
tunnel with the gateway's own key, which every machine limits to reaching its VNC server and printing whether its
screen is locked. The VNC password is still asked by the machine itself.

    remote-desk serve                    the service
    remote-desk revoke <device>|--all    end a device's sessions and screens within 5 seconds (device-gate-revoke runs it)
    remote-desk sessions                 who is on and which screens are open
    remote-desk key                      the gateway's public ssh key, for modules/butler-access
"""

import asyncio
import json
import os
import pwd
import secrets
import shutil
import socket
import sys
import time

CONFIG = json.loads(r'''@config@''')
STATE = CONFIG['state']
RUNTIME = CONFIG['runtime']
REVOKED = os.path.join(STATE, 'revoked.json')
KEY = os.path.join(STATE, 'ssh', 'id_ed25519')
KNOWN_HOSTS = os.path.join(STATE, 'known_hosts')
TUNNELS = os.path.join(RUNTIME, 'tunnels')
STATUS = os.path.join(RUNTIME, 'status.json')
SSH = CONFIG['ssh']
SS = CONFIG['ss']
ORIGIN = 'https://' + CONFIG['domain']
DEVICE_HEADER = 'X-Device-Gate-Device'

IDLE = CONFIG['idleMinutes'] * 60
LIFETIME = CONFIG['sessionHours'] * 3600


def log(*words):
    print(' '.join(str(word) for word in words), flush=True)


# ---- devices ---------------------------------------------------------------------------------------------------

def load_revoked():
    try:
        with open(REVOKED) as file:
            return json.load(file)
    except (FileNotFoundError, ValueError):
        return {}


def valid_name(name):
    return 0 < len(name) <= 32 and all(c.isascii() and (c.isalnum() or c in '-_') for c in name)


def cli_revoke(name):
    if name != '--all' and not valid_name(name):
        sys.exit('a device is a WireGuard peer name, such as ipad, or --all')
    revoked = load_revoked()
    revoked['*' if name == '--all' else name] = time.time()
    owner = pwd.getpwnam(CONFIG['user'])
    temporary = REVOKED + '.new'
    with open(os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600), 'w') as file:
        json.dump(revoked, file)
    os.chown(temporary, owner.pw_uid, owner.pw_gid)
    os.replace(temporary, REVOKED)
    print('remote-desk: ended %s; open screens close within 5 seconds' % ('every session' if name == '--all' else name + "'s sessions"))


def cli_sessions():
    try:
        with open(STATUS) as file:
            status = json.load(file)
    except FileNotFoundError:
        sys.exit('remote-desk is not running')
    if not status['sessions']:
        print('nobody is on')
    for session in status['sessions']:
        print('%s from %s, since %s, last active %s' % (session['device'], session['ip'], session['since'], session['active']))
        for screen in session['screens']:
            print('  %s (%s) since %s' % (screen['host'], screen['os'], screen['since']))


def cli_key():
    with open(KEY + '.pub') as file:
        print(file.read().strip())


# ---- the web service -------------------------------------------------------------------------------------------

def stamp(when):
    return time.strftime('%Y-%m-%dT%H:%M:%S%z', time.localtime(when))


class Session:
    def __init__(self, device, ip):
        self.token = '%s|%s' % (device, ip)
        self.device = device
        self.ip = ip
        self.since = time.time()
        self.active = self.since
        self.screens = set()

    def expired(self, now):
        return now - self.active > IDLE or now - self.since > LIFETIME


class Screen:
    def __init__(self, session, host, system, socket):
        self.session = session
        self.host = host
        self.system = system
        self.since = time.time()
        self.ssh = None
        self.socket = socket
        self.websocket = None
        self.reason = 'closed'


class Gateway:
    def __init__(self):
        self.revoked = {}
        self.revoked_mtime = None
        self.sessions = {}
        self.status = {}
        self.status_at = 0
        self.status_lock = asyncio.Lock()
        self.butler_uid = None
        try:
            self.butler_uid = pwd.getpwnam('butler').pw_uid
        except KeyError:
            pass

    # devices and sessions

    def reload_revoked(self):
        try:
            mtime = os.stat(REVOKED).st_mtime_ns
        except FileNotFoundError:
            mtime = None
        if mtime != self.revoked_mtime:
            self.revoked = load_revoked()
            self.revoked_mtime = mtime

    def is_revoked(self, session):
        return session.since <= max(self.revoked.get(session.device, 0), self.revoked.get('*', 0))

    def session_of(self, request):
        # Caddy sets the header from the device gate's answer alone, after dropping any the client sent, so only a
        # device the gate signed in reaches here; its sign-in is already bound to the WireGuard peer it came from.
        device = request.headers.get(DEVICE_HEADER, '')
        ip = client_ip(request)
        if not valid_name(device) or not ip:
            return None
        now = time.time()
        session = self.sessions.get('%s|%s' % (device, ip))
        if session is not None and (session.expired(now) or self.is_revoked(session)):
            self.end_session(session, 'idle' if now - session.active > IDLE else 'ended')
            session = None
        if session is None:
            session = Session(device, ip)
            self.sessions[session.token] = session
            log('session started', 'device=%s' % device, 'ip=%s' % ip)
        return session

    def end_session(self, session, reason):
        self.sessions.pop(session.token, None)
        for screen in list(session.screens):
            self.close_screen(screen, reason)
        log('session ended', 'device=%s' % session.device, 'ip=%s' % session.ip, 'reason=%s' % reason)

    def close_screen(self, screen, reason):
        screen.reason = reason
        if screen.websocket is not None and not screen.websocket.closed:
            asyncio.ensure_future(screen.websocket.close(code=4000, message=reason.encode()[:120]))
        if screen.ssh is not None and screen.ssh.returncode is None:
            screen.ssh.kill()

    async def sweep(self):
        while True:
            await asyncio.sleep(5)
            self.reload_revoked()
            now = time.time()
            for session in list(self.sessions.values()):
                if self.is_revoked(session):
                    self.end_session(session, 'device signed out')
                elif session.expired(now):
                    self.end_session(session, 'idle' if now - session.active > IDLE else 'session too old')
            self.write_status()

    def write_status(self):
        status = {'sessions': [{
            'device': session.device,
            'ip': session.ip,
            'since': stamp(session.since),
            'active': stamp(session.active),
            'screens': [{'host': screen.host, 'os': screen.system['os'], 'since': stamp(screen.since)} for screen in session.screens],
        } for session in self.sessions.values()]}
        temporary = STATUS + '.new'
        with open(os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600), 'w') as file:
            json.dump(status, file)
        os.replace(temporary, STATUS)

    # machine status, the same probes as butler's `mac hosts`: port 22, then the key's forced status command

    def ssh_args(self, system, *options):
        return [
            SSH, '-i', KEY,
            '-o', 'IdentitiesOnly=yes',
            '-o', 'BatchMode=yes',
            '-o', 'StrictHostKeyChecking=accept-new',
            '-o', 'UserKnownHostsFile=' + KNOWN_HOSTS,
            '-o', 'ConnectTimeout=5',
            '-o', 'ServerAliveInterval=15',
            '-o', 'ServerAliveCountMax=2',
            '-o', 'LogLevel=ERROR',
            *options,
            '%s@%s' % (system['user'], system['address']),
        ]

    async def port_open(self, address):
        try:
            _, writer = await asyncio.wait_for(asyncio.open_connection(address, 22), 3)
            writer.close()
            return True
        except (OSError, asyncio.TimeoutError):
            return False

    async def probe(self, host):
        entry = CONFIG['hosts'][host]
        opens = await asyncio.gather(*(self.port_open(system['address']) for system in entry['systems']))
        up = [system for system, open_ in zip(entry['systems'], opens) if open_]
        if not up:
            return {'state': 'down', 'detail': 'not answering: off, asleep, at a boot menu or off WireGuard'}
        system = up[0]
        result = {'state': 'up', 'os': system['os'], 'address': system['address'], 'screen': 'unknown'}
        try:
            process = await asyncio.create_subprocess_exec(
                *self.ssh_args(system), 'status',
                stdin=asyncio.subprocess.DEVNULL, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE)
            out, err = await asyncio.wait_for(process.communicate(), 12)
        except asyncio.TimeoutError:
            process.kill()
            result['detail'] = 'ssh answered but the status check timed out'
            return result
        lines = out.decode(errors='replace').replace('\r', '').split('\n')
        if process.returncode != 0:
            text = ' '.join(err.decode(errors='replace').split())
            if 'Permission denied' in text:
                result['state'] = 'refused'
                result['detail'] = 'this machine does not accept the gateway\'s key yet'
            else:
                result['detail'] = text[:200] or 'the status check failed'
            return result
        result['screen'] = lines[0].strip() or 'unknown'
        return result

    def butler_connected(self):
        """The addresses butler's own ssh connections reach, from ss, which reports every socket's owner."""
        if self.butler_uid is None:
            return set()
        try:
            out = os.popen('%s -Htne state established "( dport = :22 )"' % SS).read()
        except OSError:
            return set()
        found = set()
        for line in out.splitlines():
            fields = line.split()
            if 'uid:%d' % self.butler_uid in fields and len(fields) >= 4:
                found.add(fields[3].rsplit(':', 1)[0].strip('[]'))
        return found

    async def hosts(self):
        async with self.status_lock:
            if time.time() - self.status_at > 8:
                names = list(CONFIG['hosts'])
                results = await asyncio.gather(*(self.probe(name) for name in names))
                self.status = dict(zip(names, results))
                self.status_at = time.time()
        butler = self.butler_connected()
        listing = []
        for name, entry in CONFIG['hosts'].items():
            status = dict(self.status.get(name, {'state': 'unknown'}))
            addresses = {system['address'] for system in entry['systems']}
            status['butler'] = bool(addresses & butler)
            status['viewers'] = [
                screen.session.device for session in self.sessions.values() for screen in session.screens if screen.host == name]
            listing.append({'name': name, 'label': entry['label'], 'note': entry.get('note', ''), **status})
        return listing

    # opening a screen

    async def open_tunnel(self, screen):
        if screen.system['os'] == 'linux':
            # OpenSSH refuses unix-socket forwards to a key with permitopen, so on jimbo's NixOS the key forwards
            # nothing and its forced command carries wayvnc's socket over the session itself.
            screen.ssh = await asyncio.create_subprocess_exec(
                *self.ssh_args(screen.system), 'vnc',
                stdin=asyncio.subprocess.PIPE, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE)
            return screen.ssh.stdout, screen.ssh.stdin
        os.makedirs(TUNNELS, mode=0o700, exist_ok=True)
        if os.path.exists(screen.socket):
            os.unlink(screen.socket)
        screen.ssh = await asyncio.create_subprocess_exec(
            *self.ssh_args(
                screen.system, '-N',
                '-o', 'ExitOnForwardFailure=yes',
                '-o', 'StreamLocalBindMask=0177',
                '-o', 'StreamLocalBindUnlink=yes',
                '-L', '%s:127.0.0.1:5900' % screen.socket),
            stdin=asyncio.subprocess.DEVNULL, stdout=asyncio.subprocess.DEVNULL, stderr=asyncio.subprocess.PIPE)
        deadline = time.time() + 12
        while time.time() < deadline:
            if screen.ssh.returncode is not None:
                break
            if os.path.exists(screen.socket):
                try:
                    return await asyncio.open_unix_connection(screen.socket)
                except OSError:
                    pass
            await asyncio.sleep(0.1)
        if screen.ssh.returncode is None:
            screen.ssh.kill()
        err = (await screen.ssh.stderr.read()).decode(errors='replace')
        raise ConnectionError(' '.join(err.split())[:200] or 'the ssh tunnel did not open')


def client_ip(request):
    return request.headers.get('X-Remote-Desk-Client', '')


def main_serve():
    from aiohttp import web, WSMsgType

    gateway = Gateway()
    gateway.reload_revoked()
    shutil.rmtree(TUNNELS, ignore_errors=True)
    os.makedirs(TUNNELS, mode=0o700)

    @web.middleware
    async def headers(request, handler):
        response = await handler(request)
        response.headers['Content-Security-Policy'] = (
            "default-src 'self'; connect-src 'self' wss://%s; img-src 'self' data:; style-src 'self'; "
            "frame-ancestors 'none'; base-uri 'none'; form-action 'self'" % CONFIG['domain'])
        response.headers['X-Content-Type-Options'] = 'nosniff'
        response.headers['Referrer-Policy'] = 'no-referrer'
        if request.path.startswith('/api/'):
            response.headers['Cache-Control'] = 'no-store'
        return response

    def same_origin(request):
        return request.headers.get('Origin') in (None, ORIGIN) and request.headers.get('Sec-Fetch-Site') in (None, 'same-origin', 'none')

    def need_session(request):
        if not same_origin(request):
            raise web.HTTPForbidden(text='cross-origin request')
        gateway.reload_revoked()
        session = gateway.session_of(request)
        if session is None:
            raise web.HTTPUnauthorized(text='sign in first')
        return session

    async def index(request):
        return web.FileResponse(os.path.join(CONFIG['web'], 'index.html'))

    async def logout(request):
        session = need_session(request)
        gateway.end_session(session, 'signed out')
        # The page then goes to /.gate/logout, which clears the gate's cookie.
        return web.json_response({})

    async def me(request):
        session = need_session(request)
        return web.json_response({'device': session.device, 'idleMinutes': CONFIG['idleMinutes']})

    async def alive(request):
        session = need_session(request)
        session.active = time.time()
        return web.json_response({})

    async def hosts(request):
        need_session(request)
        return web.json_response(await gateway.hosts())

    async def screen(request):
        session = need_session(request)
        host = request.match_info['host']
        if host not in CONFIG['hosts']:
            raise web.HTTPNotFound()
        websocket = web.WebSocketResponse(protocols=('binary',), heartbeat=30, max_msg_size=4 * 1024 * 1024)
        await websocket.prepare(request)
        status = gateway.status.get(host) if time.time() - gateway.status_at < 8 else None
        if not status or status['state'] != 'up':
            status = await gateway.probe(host)
        if status['state'] != 'up':
            await websocket.close(code=4001, message=status.get('detail', status['state']).encode()[:120])
            return websocket
        system = next(s for s in CONFIG['hosts'][host]['systems'] if s['address'] == status['address'])
        current = Screen(session, host, system, os.path.join(TUNNELS, secrets.token_hex(8) + '.sock'))
        current.websocket = websocket
        session.screens.add(current)
        others = [s.session.device for s in session_screens(gateway) if s.host == host and s is not current]
        log('screen open', 'device=%s' % session.device, 'ip=%s' % session.ip, 'host=%s' % host, 'os=%s' % system['os'],
            'butler=%s' % bool({system['address']} & gateway.butler_connected()), 'others=%s' % (','.join(others) or 'none'))
        sent = received = 0
        try:
            try:
                reader, writer = await gateway.open_tunnel(current)
            except ConnectionError as error:
                current.reason = 'tunnel failed: %s' % error
                await websocket.close(code=4002, message=str(error).encode()[:120])
                return websocket

            async def upstream():
                nonlocal sent
                async for message in websocket:
                    if message.type == WSMsgType.BINARY:
                        writer.write(message.data)
                        sent += len(message.data)
                        await writer.drain()
                    elif message.type in (WSMsgType.CLOSE, WSMsgType.ERROR):
                        break
                current.reason = current.reason if current.reason != 'closed' else 'viewer closed'

            async def downstream():
                nonlocal received
                while True:
                    data = await reader.read(256 * 1024)
                    if not data:
                        if current.reason == 'closed':
                            current.reason = 'machine closed the connection'
                            if current.ssh is not None and current.ssh.stderr is not None and current.system['os'] == 'linux':
                                await asyncio.sleep(0.2)
                                if current.ssh.returncode is not None:
                                    err = ' '.join((await current.ssh.stderr.read()).decode(errors='replace').split())
                                    current.reason = err[:200] or current.reason
                        break
                    received += len(data)
                    await websocket.send_bytes(data)

            tasks = [asyncio.ensure_future(upstream()), asyncio.ensure_future(downstream())]
            await asyncio.wait(tasks, return_when=asyncio.FIRST_COMPLETED)
            for task in tasks:
                task.cancel()
            writer.close()
        except (ConnectionError, OSError) as error:
            current.reason = 'error: %s' % error
        finally:
            session.screens.discard(current)
            if current.ssh is not None and current.ssh.returncode is None:
                current.ssh.kill()
            if os.path.exists(current.socket):
                os.unlink(current.socket)
            if not websocket.closed:
                await websocket.close(code=4003, message=current.reason.encode()[:120])
            log('screen closed', 'device=%s' % session.device, 'host=%s' % host, 'minutes=%.1f' % ((time.time() - current.since) / 60),
                'sent=%d' % sent, 'received=%d' % received, 'reason=%s' % current.reason)
        return websocket

    def session_screens(gateway):
        return [screen for session in gateway.sessions.values() for screen in session.screens]

    app = web.Application(middlewares=[headers], client_max_size=4096)
    app.router.add_get('/', index)
    app.router.add_post('/api/logout', logout)
    app.router.add_get('/api/me', me)
    app.router.add_post('/api/alive', alive)
    app.router.add_get('/api/hosts', hosts)
    app.router.add_get('/api/screen/{host}', screen)
    app.router.add_static('/novnc/', CONFIG['novnc'], follow_symlinks=False)
    app.router.add_static('/static/', CONFIG['web'], follow_symlinks=False)

    async def start(app):
        app['sweep'] = asyncio.ensure_future(gateway.sweep())

    app.on_startup.append(start)
    listen = os.path.join(RUNTIME, 'http.sock')
    if os.path.exists(listen):
        os.unlink(listen)
    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.bind(listen)
    os.chmod(listen, 0o660)
    log('remote-desk listening on', listen, 'for', ORIGIN)
    web.run_app(app, sock=server, print=None, access_log=None)


def main():
    verb = sys.argv[1] if len(sys.argv) > 1 else ''
    args = sys.argv[2:]
    if verb == 'serve':
        main_serve()
        return
    if verb in ('revoke', 'sessions', 'key') and os.geteuid() != 0:
        sys.exit('run it with sudo: remote-desk %s' % ' '.join(sys.argv[1:]))
    if verb == 'revoke' and len(args) == 1:
        cli_revoke(args[0])
    elif verb == 'sessions':
        cli_sessions()
    elif verb == 'key':
        cli_key()
    else:
        sys.exit(__doc__)


if __name__ == '__main__':
    main()
