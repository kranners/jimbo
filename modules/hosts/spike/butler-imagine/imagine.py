import base64
import contextlib
import os
import secrets
import sys
import time
from datetime import datetime, timezone

import requests

API = "https://api.openai.com/v1/images"
MODEL = "gpt-image-2.5-flare"
QUALITY = "medium"
FORMAT = "jpeg"
AVATAR = "@avatar@"
OUTBOX = "/var/lib/butler/outbox"
OUTBOX_DAYS = 2
TIMEOUT_SECONDS = 55
EX_TEMPFAIL = 75

SIZES = {
    "square": "1024x1024",
    "portrait": "1024x1536",
    "landscape": "1536x1024",
}

IN_CHARACTER = "The reference image is Butler, the character in this picture. Keep his look, colours and proportions recognisably the same. "

USAGE = """usage: imagine <square|portrait|landscape>         (prompt on stdin)
       imagine butler <square|portrait|landscape>  (prompt on stdin)"""


def usage():
    print(USAGE, file=sys.stderr)
    sys.exit(2)


def fail(message, status=1):
    print(f"imagine: {message}", file=sys.stderr)
    sys.exit(status)


def parse(args):
    match args:
        case [shape] if shape in SIZES:
            return False, SIZES[shape]
        case ["butler", shape] if shape in SIZES:
            return True, SIZES[shape]
    usage()


def api_key():
    directory = os.environ.get("CREDENTIALS_DIRECTORY")
    if not directory:
        fail("no OpenAI API key: CREDENTIALS_DIRECTORY is unset")
    try:
        with open(os.path.join(directory, "openai-api-key")) as file:
            return file.read().strip()
    except FileNotFoundError:
        fail("no OpenAI API key: the openai-api-key credential is missing")
    except OSError as error:
        fail(f"cannot read the openai-api-key credential: {error.strerror}")


def request(key, prompt, size, in_character):
    fields = {
        "model": MODEL,
        "prompt": prompt,
        "size": size,
        "quality": QUALITY,
        "output_format": FORMAT,
    }
    headers = {"Authorization": f"Bearer {key}"}
    if not in_character:
        return requests.post(f"{API}/generations", headers=headers, json=fields, timeout=TIMEOUT_SECONDS)
    fields["prompt"] = IN_CHARACTER + prompt
    with open(AVATAR, "rb") as avatar:
        return requests.post(
            f"{API}/edits",
            headers=headers,
            data=fields,
            files=[("image[]", ("butler.png", avatar, "image/png"))],
            timeout=TIMEOUT_SECONDS,
        )


def error_message(response):
    try:
        error = response.json()["error"]
        return f"{error.get('code') or error.get('type') or response.status_code}: {error['message']}"
    except (ValueError, KeyError, TypeError):
        return f"HTTP {response.status_code}: {response.text[:300]}"


def generate(key, prompt, size, in_character):
    try:
        response = request(key, prompt, size, in_character)
    except requests.Timeout:
        fail(f"OpenAI took longer than {TIMEOUT_SECONDS} s; try again, or with a simpler prompt", EX_TEMPFAIL)
    except requests.RequestException as error:
        fail(f"could not reach OpenAI: {error}", EX_TEMPFAIL)
    if not response.ok:
        fail(f"OpenAI refused: {error_message(response)}".replace("\n", " "))
    try:
        return base64.b64decode(response.json()["data"][0]["b64_json"])
    except (ValueError, KeyError, IndexError, TypeError):
        fail(f"OpenAI answered without an image: {response.text[:300]}".replace("\n", " "))


def clear_old_outbox():
    cutoff = time.time() - OUTBOX_DAYS * 86400
    for entry in os.scandir(OUTBOX):
        with contextlib.suppress(FileNotFoundError):
            if entry.is_file() and entry.stat().st_mtime < cutoff:
                os.remove(entry.path)


def save(image):
    os.makedirs(OUTBOX, exist_ok=True)
    clear_old_outbox()
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    path = os.path.join(OUTBOX, f"imagine-{stamp}-{secrets.token_hex(3)}.jpg")
    with open(path, "wb") as file:
        file.write(image)
    return path


def main():
    in_character, size = parse(sys.argv[1:])
    prompt = sys.stdin.read().strip()
    if not prompt:
        fail("the prompt goes on stdin, and it was empty", 2)
    image = generate(api_key(), prompt, size, in_character)
    print(save(image))


if __name__ == "__main__":
    main()
