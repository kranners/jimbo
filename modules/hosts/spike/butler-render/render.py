import json
import os
import re
import secrets
import sys
import threading
import time
from datetime import datetime, timezone

os.environ["PLAYWRIGHT_BROWSERS_PATH"] = "@browsers@"

from playwright.sync_api import Error, sync_playwright

OUTBOX = "@outbox@"
LIBRARIES = ["@vega@", "@vegaLite@", "@vegaEmbed@", "@mermaid@"]
MODES = ["html", "svg", "mermaid", "vega-lite"]
DEFAULT_WIDTH = 1000
MIN_WIDTH = 320
MAX_WIDTH = 2400
MAX_HEIGHT = 8000
MAX_BYTES = 25 * 1000 * 1000
DEADLINE_SECONDS = 30
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
        return json.loads(source)
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


def isolate(context):
    context.route("**/*", lambda route: route.abort())
    context.route_web_socket("**/*", lambda socket: None)


def render(mode, width, source):
    problems = []
    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(args=CHROMIUM_ARGS)
        context = browser.new_context(
            offline=True,
            accept_downloads=False,
            service_workers="block",
            viewport={"width": width, "height": 600},
            device_scale_factor=2,
        )
        isolate(context)
        context.set_default_timeout(DEADLINE_SECONDS * 1000)
        page = context.new_page()
        page.on("pageerror", lambda error: problems.append(str(error)))
        page.on("console", lambda message: message.type == "error" and problems.append(message.text))

        if mode == "html":
            page.set_content(with_libraries(source), wait_until="load")
            page.evaluate(SETTLE)
            height = page.evaluate(MEASURE)
            clip = {"x": 0, "y": 0, "width": width, "height": min(height, MAX_HEIGHT)}
            image = page.screenshot(full_page=True, clip=clip, type="png")
        else:
            page.set_content(with_libraries(SHELL))
            page.evaluate(DRAW[mode], [source, width])
            page.evaluate(SETTLE)
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
    print(path)


if __name__ == "__main__":
    main()
