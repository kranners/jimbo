import json
import mimetypes
import os
import re
import stat
import secrets
import subprocess
import sys
import threading
import time
from datetime import datetime, timezone
from urllib.parse import unquote, urlsplit

os.environ["PLAYWRIGHT_BROWSERS_PATH"] = "@browsers@"

from playwright.sync_api import Error, sync_playwright

OUTBOX = "@outbox@"
ASSET = "@asset@"
# Butler's own pictures, the only files a page may load, by reference: asset://<name>, outbox://<file>, mood://<name> and scene://<group>/<name>.
STORE = "@store@"
MOODS = "@moods@"
SCENES = "@scenes@"
SCENE_GROUPS = "@sceneGroups@".split(":")
LIBRARIES = ["@vega@", "@vegaLite@", "@vegaEmbed@", "@mermaid@"]
MODES = ["html", "svg", "mermaid", "vega-lite"]
DEFAULT_WIDTH = 1000
MIN_WIDTH = 320
MAX_WIDTH = 2400
MAX_HEIGHT = 8000
MAX_BYTES = 25 * 1000 * 1000
DEADLINE_SECONDS = 30
MAX_PICTURE_BYTES = 25 * 1000 * 1000
OUTBOX_DAYS = 2

USAGE = """usage: render html [width]
       render svg [width]
       render mermaid [width]
       render vega-lite [width]
the source on stdin; width in CSS pixels, 320 to 2400, 1000 unless given"""

CHROMIUM_ARGS = [
    "--host-resolver-rules=MAP * ~NOTFOUND",
    "--proxy-server=127.0.0.1:9",
    "--proxy-bypass-list=<-loopback>",
    "--force-webrtc-ip-handling-policy=disable_non_proxied_udp",
    "--webrtc-ip-handling-policy=disable_non_proxied_udp",
    "--disable-background-networking",
    "--dns-prefetch-disable",
    "--no-pings",
]

# The page is served from this made-up origin, which never reaches the network: every request to it is answered from Butler's own files or refused.
ORIGIN = "http://butler.render"
# A reference where a URL stands, after a quote, ( or =, or a srcset's comma, so the same words in the page's text stay as written.
REFERENCE = re.compile(r"""(?:(?<=["'(=,])|(?<=, )|(?<=\( ))\s*(asset|outbox|mood|scene)://""", re.IGNORECASE)
NAME = re.compile(r"[A-Za-z0-9][A-Za-z0-9._ +-]{0,199}")
PICTURES = {
    ".png": "image/png",
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".webp": "image/webp",
    ".gif": "image/gif",
    ".svg": "image/svg+xml",
    ".avif": "image/avif",
    ".bmp": "image/bmp",
    ".ico": "image/x-icon",
}

THEME = """
:where(html) {
  font-family: system-ui, -apple-system, "Segoe UI", Roboto, "Noto Sans", "Helvetica Neue", Arial, sans-serif, "Noto Color Emoji";
  font-size: 16px;
  line-height: 1.45;
  color: #1f2328;
  background: #ffffff;
}
:where(body) { margin: 16px; }
"""

SHELL = """<!doctype html>
<html><head><meta charset="utf-8"><style>
body { margin: 0; }
#figure { display: inline-block; padding: 16px; background: #ffffff; }
</style></head><body><div id="figure"></div></body></html>"""

PREPARE = """
mermaid.initialize({ startOnLoad: false, theme: "default", securityLevel: "strict" });
"""

DRAW = {
    "svg": """async ([source, width]) => {
        document.getElementById("figure").innerHTML = source;
        const svg = document.querySelector("#figure svg");
        if (!svg) throw new Error("the input holds no <svg> element");
        if (!svg.getAttribute("width")) svg.setAttribute("width", width - 32);
    }""",
    "mermaid": """async ([source]) => {
        const figure = document.getElementById("figure");
        figure.style.display = "block";
        figure.innerHTML = (await mermaid.render("diagram", source)).svg;
        const svg = figure.querySelector("svg");
        svg.style.width = `${svg.getBoundingClientRect().width}px`;
        svg.style.maxWidth = "none";
        figure.style.display = "";
    }""",
    "vega-lite": """async ([spec, width]) => {
        const config = { view: { continuousWidth: width - 160, continuousHeight: Math.round(width * 0.45) } };
        await vegaEmbed("#figure", spec, { renderer: "svg", actions: false, config });
    }""",
}

MEASURE = """() => {
    const root = document.documentElement;
    if (root.scrollHeight > innerHeight) return root.scrollHeight;
    const content = document.createRange();
    content.selectNodeContents(document.body);
    const bottom = content.getBoundingClientRect().bottom + parseFloat(getComputedStyle(document.body).marginBottom);
    return Math.max(1, Math.ceil(bottom));
}"""

SETTLE = """async () => {
    if (document.querySelector(".mermaid")) await mermaid.run();
    if (window.ready) await window.ready;
    await document.fonts.ready;
    await Promise.all([...document.images].map((image) => image.decode().catch(() => {})));
    await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
}"""


def fail(message, code=1):
    print(f"render: {message}", file=sys.stderr)
    sys.exit(code)


def usage():
    print(USAGE, file=sys.stderr)
    sys.exit(2)


def parse_args(args):
    if not 1 <= len(args) <= 2 or args[0] not in MODES:
        usage()
    if len(args) == 1:
        return args[0], DEFAULT_WIDTH
    if not args[1].isdigit():
        usage()
    return args[0], max(MIN_WIDTH, min(MAX_WIDTH, int(args[1])))


def read_source(mode):
    source = sys.stdin.read()
    if not source.strip():
        fail("the source on stdin is empty", 2)
    if mode != "vega-lite":
        return source
    try:
        return json.loads(by_reference(source))
    except json.JSONDecodeError as error:
        fail(f"the Vega-Lite spec is not valid JSON: {error}", 2)


def outbox_path():
    os.makedirs(OUTBOX, exist_ok=True)
    cutoff = time.time() - OUTBOX_DAYS * 86400
    for entry in os.scandir(OUTBOX):
        if entry.is_file(follow_symlinks=False) and entry.stat().st_mtime < cutoff:
            os.remove(entry.path)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    return os.path.join(OUTBOX, f"render-{stamp}-{secrets.token_hex(4)}.png")


def with_libraries(document):
    scripts = []
    for path in LIBRARIES:
        with open(path) as file:
            scripts.append(file.read())
    scripts.append(PREPARE)
    sources = [f"<style>{THEME}</style>"] + [
        "<script>" + script.replace("</script", "<\\/script") + "</script>" for script in scripts
    ]
    start = re.match(r"\s*(<!doctype[^>]*>)?", document, re.IGNORECASE).end()
    return document[:start] + "".join(sources) + document[start:]


class Refused(Exception):
    pass


def by_reference(source):
    """asset://, outbox://, mood:// and scene:// become paths on the page's own origin, so img src, srcset, CSS url() and SVG href all load them."""
    return REFERENCE.sub(lambda match: match.group(0)[: match.start(1) - match.start(0)] + f"{ORIGIN}/{match.group(1).lower()}/", source)


def contained(root, *names):
    """The file under root that names point to, refusing anything that climbs out of it or passes through a symlink."""
    for name in names:
        if not NAME.fullmatch(name) or ".." in name:
            raise Refused(f"{name!r} is not a plain file name")
    path = os.path.join(root, *names)
    base = os.path.realpath(root)
    real = os.path.realpath(path)
    if os.path.commonpath([base, real]) != base or os.path.relpath(real, base) != os.path.join(*names):
        raise Refused("it leads outside Butler's pictures or through a symlink")
    return path


def asset_file(name):
    try:
        with open(os.path.join(STORE, "manifest.json")) as file:
            assets = json.load(file).get("assets", [])
    except (OSError, ValueError):
        raise Refused("the asset store cannot be read")
    entry = next((a for a in assets if a.get("name") == name), None)
    if entry is None:
        raise Refused(f"no asset is named {name!r}; try `asset list`")
    parts = str(entry.get("file", "")).split("/")
    if len(parts) != 2 or parts[0] != "files":
        raise Refused(f"asset {name!r} is not a stored file")
    return contained(STORE, *parts)


def with_extension(name):
    return name if os.path.splitext(name)[1] else name + ".webp"


def locate(url):
    """The file a request for one of Butler's own pictures names, or Refused saying why."""
    parts = urlsplit(url)
    if f"{parts.scheme}://{parts.netloc}" != ORIGIN:
        raise Refused("the page has no network; use asset://, outbox://, mood:// or scene:// for Butler's own pictures, or a data: URI")
    segments = [unquote(segment) for segment in parts.path.split("/")[1:]] or [""]
    kind, names = segments[0], segments[1:]
    if kind == "asset" and len(names) == 1:
        return asset_file(names[0])
    if kind == "outbox" and len(names) == 1:
        return contained(OUTBOX, names[0])
    if kind == "mood" and len(names) == 1:
        return contained(MOODS, with_extension(names[0]))
    if kind == "scene" and len(names) == 2:
        if names[0] not in SCENE_GROUPS:
            raise Refused(f"there is no scene group {names[0]!r}")
        return contained(SCENES, names[0], with_extension(names[1]))
    raise Refused("only asset://<name>, outbox://<file>, mood://<name> and scene://<group>/<name> load")


def picture(path):
    """A picture's bytes and type, opened without following a symlink, a regular file and no bigger than Discord takes."""
    kind = PICTURES.get(os.path.splitext(path)[1].lower())
    if kind is None:
        raise Refused("only pictures load: " + ", ".join(sorted(PICTURES)))
    try:
        descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC)
    except OSError as error:
        raise Refused("there is no such file" if error.errno == 2 else f"it cannot be opened: {error.strerror}")
    with os.fdopen(descriptor, "rb") as file:
        info = os.fstat(file.fileno())
        if not stat.S_ISREG(info.st_mode):
            raise Refused("it is not a regular file")
        if info.st_size > MAX_PICTURE_BYTES:
            raise Refused(f"it is over {MAX_PICTURE_BYTES} bytes")
        return file.read(MAX_PICTURE_BYTES + 1), kind


def shown(url):
    return url if len(url) <= 120 else url[:117] + "..."


def isolate(context, document, problems, pending):
    """Every request is answered here: the page itself, Butler's own pictures, and a refusal for everything else."""

    def answer(route):
        url = route.request.url
        if url == ORIGIN + "/":
            return route.fulfill(status=200, content_type="text/html; charset=utf-8", body=document[0])
        try:
            body, kind = picture(locate(url))
        except Refused as why:
            problems.append(f"refused {shown(url)}: {why}")
            return route.abort("blockedbyclient")
        route.fulfill(status=200, content_type=kind, body=body)

    context.route("**/*", answer)
    context.route_web_socket("**/*", lambda socket: None)
    context.on("request", lambda request: pending.add(request))
    context.on("requestfinished", lambda request: pending.discard(request))
    context.on("requestfailed", lambda request: pending.discard(request))


def quiet(page, pending):
    """Waits for every picture the page asked for, CSS backgrounds and SVG images included, then for a frame to paint them."""
    deadline = time.monotonic() + 10
    while pending and time.monotonic() < deadline:
        page.wait_for_timeout(50)
    page.evaluate(SETTLE)


def render(mode, width, source):
    problems = []
    pending = set()
    document = [""]
    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(args=CHROMIUM_ARGS)
        context = browser.new_context(
            offline=True,
            accept_downloads=False,
            service_workers="block",
            viewport={"width": width, "height": 600},
            device_scale_factor=2,
        )
        isolate(context, document, problems, pending)
        context.set_default_timeout(DEADLINE_SECONDS * 1000)
        page = context.new_page()
        page.on("pageerror", lambda error: problems.append(str(error)))
        # A refused request is already a problem of its own, with why.
        page.on("console", lambda message: message.type == "error" and not message.text.startswith("Failed to load resource") and problems.append(message.text))

        if mode == "html":
            document[0] = with_libraries(by_reference(source))
            page.goto(ORIGIN + "/", wait_until="load")
            page.evaluate(SETTLE)
            quiet(page, pending)
            height = page.evaluate(MEASURE)
            clip = {"x": 0, "y": 0, "width": width, "height": min(height, MAX_HEIGHT)}
            image = page.screenshot(full_page=True, clip=clip, type="png")
        else:
            document[0] = with_libraries(SHELL)
            page.goto(ORIGIN + "/", wait_until="load")
            page.evaluate(DRAW[mode], [by_reference(source) if mode == "svg" else source, width])
            page.evaluate(SETTLE)
            quiet(page, pending)
            figure = page.locator("#figure")
            box = figure.bounding_box()
            height = box["height"] if box else 0
            if height > MAX_HEIGHT:
                fail(f"the picture is {round(height)} px tall, over the {MAX_HEIGHT} px limit; split it up")
            if box and box["width"] > MAX_WIDTH:
                fail(f"the picture is {round(box['width'])} px wide, over the {MAX_WIDTH} px limit; make it narrower")
            image = figure.screenshot(type="png")
        browser.close()

    if height > MAX_HEIGHT:
        problems.append(f"the page is {height} px tall, so only the top {MAX_HEIGHT} px were kept")
    return image, problems


def explain(error):
    lines = error.message.split("Call log:")[0].strip().splitlines()
    return "\n".join(line for line in lines if not line.lstrip().startswith("at "))[:2000]


def watchdog():
    print(f"render: gave up after {DEADLINE_SECONDS} s", file=sys.stderr)
    sys.stderr.flush()
    os._exit(1)


def register(path, description):
    """Saves what was made in butler's asset store, so another thread can find it; never fails the picture."""
    if os.environ.get("BUTLER_ASSETS_AUTO") == "0":
        return
    try:
        subprocess.run([ASSET, "auto", path, description], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=20)
    except (OSError, subprocess.SubprocessError):
        pass


def main():
    mode, width = parse_args(sys.argv[1:])
    source = read_source(mode)

    timer = threading.Timer(DEADLINE_SECONDS, watchdog)
    timer.daemon = True
    timer.start()
    try:
        image, problems = render(mode, width, source)
    except Error as error:
        fail(explain(error))
    timer.cancel()

    if len(image) > MAX_BYTES:
        fail(f"the picture is {len(image)} bytes, over Discord's 25 MB limit; use a smaller width")
    for problem in problems:
        print(f"render: warning: {problem}", file=sys.stderr)
    path = outbox_path()
    with open(path, "wb") as file:
        file.write(image)
    register(path, f"made by render {mode}")
    print(path)


if __name__ == "__main__":
    main()
