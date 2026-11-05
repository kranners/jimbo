"""render's pictures by reference, in a real Chromium against fixture folders: Butler's own pictures load, and nothing else does."""

import importlib.util
import io
import json
import os
import socket
import sys
import tempfile
import threading

from PIL import Image

spec = importlib.util.spec_from_file_location("render", sys.argv[1])
render = importlib.util.module_from_spec(spec)
spec.loader.exec_module(render)

root = tempfile.mkdtemp()
secret = os.path.join(root, "secret")
for folder in ["assets/files", "outbox", "scenes/general", "scenes/work", secret]:
    os.makedirs(os.path.join(root, folder), exist_ok=True)


def square(path, colour):
    Image.new("RGB", (40, 40), colour).save(path)


RED, GREEN, BLUE, MAGENTA = (220, 20, 20), (20, 180, 40), (30, 60, 220), (200, 0, 200)
square(os.path.join(root, "assets/files/portrait.png"), RED)
square(os.path.join(root, "outbox/imagine-1.png"), GREEN)
square(os.path.join(root, "scenes/general/home.webp"), BLUE)
square(os.path.join(secret, "passwd.png"), MAGENTA)
os.symlink(os.path.join(secret, "passwd.png"), os.path.join(root, "outbox/sneaky.png"))
os.symlink(secret, os.path.join(root, "outbox/linked"))
with open(os.path.join(root, "outbox/notes.txt"), "w") as file:
    file.write("not a picture")
with open(os.path.join(root, "assets/manifest.json"), "w") as file:
    json.dump(
        {
            "assets": [
                {"name": "portrait", "file": "files/portrait.png", "kind": "image"},
                {"name": "escape", "file": "../secret/passwd.png", "kind": "image"},
            ]
        },
        file,
    )

render.STORE = os.path.join(root, "assets")
render.OUTBOX = os.path.join(root, "outbox")
render.SCENES = os.path.join(root, "scenes")
render.SCENE_GROUPS = ["general", "work"]

failures = []


def check(name, condition, detail=""):
    print(("ok   " if condition else "FAIL ") + name + (f": {detail}" if detail and not condition else ""))
    if not condition:
        failures.append(name)


def colour_at(image, x, y):
    return Image.open(io.BytesIO(image)).convert("RGB").getpixel((x * 2, y * 2))


def near(a, b):
    return all(abs(p - q) < 40 for p, q in zip(a, b))


def page(src, style=""):
    return f'<!doctype html><style>body{{margin:0}} .box{{width:80px;height:80px;display:block{style}}}</style><img class="box" src="{src}">'


# Butler's own pictures load.
for name, src, colour in [
    ("asset:// loads from the asset store", "asset://portrait", RED),
    ("outbox:// loads from the outbox", "outbox://imagine-1.png", GREEN),
    ("scene:// loads a scene picture", "scene://general/home", BLUE),
    ("a relative path on the page's origin loads", "asset/portrait", RED),
]:
    image, problems = render.render("html", 400, page(src))
    check(name, near(colour_at(image, 40, 40), colour), f"{colour_at(image, 40, 40)} {problems}")

image, problems = render.render("html", 400, page("mood://content"))
check("mood:// loads a mood picture", colour_at(image, 40, 40) != (255, 255, 255), str(problems))

css = '<!doctype html><style>body{margin:0} div{width:80px;height:80px;background:url("asset://portrait") center/cover}</style><div></div>'
image, problems = render.render("html", 400, css)
check("CSS url() loads by reference", near(colour_at(image, 40, 40), RED), f"{colour_at(image, 40, 40)} {problems}")

svg = '<svg xmlns="http://www.w3.org/2000/svg" width="200" height="120"><image href="outbox://imagine-1.png" x="0" y="0" width="120" height="120"/></svg>'
image, problems = render.render("svg", 400, svg)
check("render svg loads an <image> by reference", near(colour_at(image, 16 + 60, 16 + 60), GREEN), f"{colour_at(image, 76, 76)} {problems}")

srcset = '<!doctype html><style>body{margin:0} img{width:80px;height:80px;display:block}</style><img srcset="outbox://imagine-1.png 1x, asset://portrait 2x"><p>see mood://content</p>'
image, problems = render.render("html", 400, srcset)
check("srcset loads by reference past its first entry", near(colour_at(image, 40, 40), RED), f"{colour_at(image, 40, 40)} {problems}")
check("a reference in the page's text stays as written", render.by_reference(srcset).endswith("<p>see mood://content</p>"), render.by_reference(srcset))

# Nothing else does: traversal, symlinks, other files, file:// and the network are refused and show nothing.
for name, src, why in [
    ("../ traversal out of the asset store", "asset://../secret/passwd.png", "only asset://"),
    ("a name of dots", "outbox://..%2E", "plain file name"),
    ("encoded traversal out of the outbox", "outbox://..%2Fsecret%2Fpasswd.png", "plain file name"),
    ("an asset whose stored file climbs out", "asset://escape", "not a stored file"),
    ("a symlink in the outbox", "outbox://sneaky.png", "symlink"),
    ("a symlinked folder in the outbox", "outbox://linked%2Fpasswd.png", "plain file name"),
    ("a file that is not a picture", "outbox://notes.txt", "only pictures"),
    ("an unknown scene group", "scene://secret/passwd", "no scene group"),
    ("an unknown asset", "asset://nobody", "no asset"),
    ("file:///etc/passwd", "file:///etc/passwd", "local resource"),
    ("file:// of a real picture", "file://" + os.path.join(secret, "passwd.png"), "local resource"),
    ("the cloud metadata address", "http://169.254.169.254/latest/meta-data", "no network"),
    ("a public site", "https://example.com/logo.png", "no network"),
    ("another path on the page's own origin", "/etc/passwd", "only asset://"),
]:
    image, problems = render.render("html", 400, page(src, ";background:white"))
    shown = colour_at(image, 40, 40)
    check(f"{name} is refused", not near(shown, MAGENTA) and not near(shown, RED) and not near(shown, GREEN), str(shown))
    check(f"{name} says why", any(why in problem for problem in problems), str(problems))

image, problems = render.render("html", 400, '<!doctype html><script>fetch("http://169.254.169.254/").then(() => document.title = "reached")</script>')
check("a fetch to the network is refused", any("no network" in problem for problem in problems), str(problems))

# Past Playwright's routes: a SharedWorker's fetch and WebRTC's STUN, which only Chromium's dead proxy, resolver and UDP policy stop, to listeners on loopback.
heard = []
tcp = socket.socket()
tcp.bind(("127.0.0.1", 0))
tcp.listen()
udp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
udp.bind(("127.0.0.1", 0))
for listener in (tcp, udp):
    listener.settimeout(0.2)


def listen():
    while not done.is_set():
        for listener, take in ((tcp, tcp.accept), (udp, lambda: udp.recvfrom(2048))):
            try:
                take()
                heard.append(listener.type)
            except OSError:
                pass


done = threading.Event()
thread = threading.Thread(target=listen, daemon=True)
thread.start()
leaky = f"""<!doctype html><script>
const worker = new SharedWorker(URL.createObjectURL(new Blob(["fetch('http://127.0.0.1:{tcp.getsockname()[1]}/').catch(() => {{}})"], {{ type: "text/javascript" }})));
const peer = new RTCPeerConnection({{ iceServers: [{{ urls: "stun:127.0.0.1:{udp.getsockname()[1]}" }}] }});
peer.createDataChannel("x");
window.ready = peer.createOffer().then((offer) => peer.setLocalDescription(offer)).then(() => new Promise((resolve) => setTimeout(resolve, 2000)));
</script>"""
render.render("html", 400, leaky)
done.set()
thread.join()
check("a SharedWorker's fetch and WebRTC's STUN reach nothing on loopback", not heard, str(heard))

if failures:
    print(f"{len(failures)} failed")
    sys.exit(1)
print("every check passed")
