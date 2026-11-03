import asyncio
import concurrent.futures
import contextlib
import os
import secrets
import sys
import time
import wave
from datetime import datetime, timezone

import requests
from wyoming.audio import AudioChunk, AudioStart, AudioStop
from wyoming.client import AsyncTcpClient
from wyoming.tts import Synthesize, SynthesizeVoice

SPEECH_API = "https://api.openai.com/v1/audio/speech"
# Free: it hands back an ephemeral key for a browser, which is thrown away unread.
REALTIME_SECRET_API = "https://api.openai.com/v1/realtime/client_secrets"
REALTIME_MODEL = "gpt-realtime-2.1"
SPEECH_MODEL = "gpt-4o-mini-tts"
# OpenAI's estimate for gpt-4o-mini-tts, in US dollars a minute of speech.
USD_PER_MINUTE = 0.015
# The voices the realtime API speaks in, so a sample can be chosen with /realtime voice.
OPENAI_VOICES = ["alloy", "ash", "ballad", "cedar", "coral", "echo", "marin", "sage", "shimmer", "verse"]
# Kokoro's British male voices, which suit Butler, and the rest Kokoro has.
KOKORO_DEFAULT = ["bm_george", "bm_lewis", "bm_daniel", "bm_fable"]
KOKORO_VOICES = KOKORO_DEFAULT + [
    "af_alloy", "af_aoede", "af_bella", "af_heart", "af_jessica", "af_kore", "af_nicole", "af_nova",
    "af_river", "af_sarah", "af_sky", "am_adam", "am_echo", "am_eric", "am_fenrir", "am_liam",
    "am_michael", "am_onyx", "am_puck", "am_santa", "bf_alice", "bf_emma", "bf_isabella", "bf_lily",
]
KOKORO_HOST = "127.0.0.1"
KOKORO_PORT = 10200
STYLE_FILE = "@style@"
OUTBOX = "/var/lib/butler/outbox"
OUTBOX_DAYS = 2
MAX_CHARS = 300
MAX_VOICES = 16
TIMEOUT_SECONDS = 45

# The dedicated audio key when one is written, else the key imagine uses.
KEY_CREDENTIALS = [("openai-audio-key", "the dedicated audio key"), ("openai-api-key", "the shared imagine key")]

USAGE = f"""usage: voice-sample [voice...]   (the line to say on stdin, at most {MAX_CHARS} characters)
       voice-sample --check        (checks the OpenAI key may speak and open realtime calls)
  voices: {', '.join(OPENAI_VOICES)} (OpenAI, in Butler's voice brief),
          {', '.join(KOKORO_DEFAULT)} or any other Kokoro voice (local),
          openai, kokoro, or nothing for both sets"""


def fail(message, status=1):
    print(f"voice-sample: {message}", file=sys.stderr)
    sys.exit(status)


def voices(args):
    if not args:
        return OPENAI_VOICES + KOKORO_DEFAULT
    chosen = []
    for arg in (a.lower() for a in args):
        group = {"openai": OPENAI_VOICES, "kokoro": KOKORO_DEFAULT}.get(arg)
        if group is None and arg not in OPENAI_VOICES and arg not in KOKORO_VOICES:
            print(USAGE, file=sys.stderr)
            fail(f"unknown voice {arg}", 2)
        chosen += [v for v in group or [arg] if v not in chosen]
    if len(chosen) > MAX_VOICES:
        fail(f"at most {MAX_VOICES} voices a run", 2)
    return chosen


def style():
    with open(STYLE_FILE) as file:
        return file.read().strip()


def api_key():
    """The first key credential that holds a key, and which one it was."""
    directory = os.environ.get("CREDENTIALS_DIRECTORY") or ""
    for name, label in KEY_CREDENTIALS:
        try:
            with open(os.path.join(directory, name)) as file:
                key = file.read().strip()
        except OSError:
            continue
        if key:
            return key, label
    fail("no OpenAI API key: neither the openai-audio-key nor the openai-api-key credential holds one")


def refusal(response, permission):
    """OpenAI's refusal in plain words, naming the permission a restricted key lacks."""
    try:
        message = response.json()["error"]["message"]
    except (ValueError, KeyError, TypeError):
        message = response.text[:200]
    message = " ".join(str(message).split())
    if "missing scopes" in message.lower() or "insufficient permissions" in message.lower():
        scopes = message.lower().split("missing scopes:", 1)[-1].split(". ")[0].strip(" .") if "missing scopes:" in message.lower() else ""
        return f"the OpenAI key lacks the {permission} permission" + (f" (missing scopes: {scopes})" if scopes else "")
    return f"OpenAI refused (HTTP {response.status_code}): {message}"


def post(url, key, body):
    try:
        return requests.post(url, headers={"Authorization": f"Bearer {key}"}, json=body, timeout=TIMEOUT_SECONDS)
    except requests.RequestException as error:
        raise RuntimeError(f"could not reach OpenAI: {type(error).__name__}")


def openai_sample(key, voice, text):
    response = post(SPEECH_API, key, {"model": SPEECH_MODEL, "voice": voice, "input": text, "instructions": style(), "response_format": "pcm"})
    if not response.ok:
        raise RuntimeError(refusal(response, "Audio (speech)"))
    # 24 kHz mono 16-bit PCM.
    return response.content, 24000, 2, 1


def check():
    """Tests the key's speech and realtime permissions: realtime for free, speech with one spoken full stop, a hundredth of a cent at most."""
    key, label = api_key()
    print(f"voice-sample: using {label}")
    probes = [
        ("speech", "Audio (speech)", SPEECH_API, {"model": SPEECH_MODEL, "voice": "cedar", "input": ".", "response_format": "pcm"}),
        ("realtime", "Realtime", REALTIME_SECRET_API, {"session": {"type": "realtime", "model": REALTIME_MODEL}}),
    ]
    problems = []
    for name, permission, url, body in probes:
        try:
            response = post(url, key, body)
            result = "ok" if response.ok else refusal(response, permission)
        except RuntimeError as error:
            result = str(error)
        print(f"voice-sample: {name}: {result}")
        if result != "ok":
            problems.append(f"{name}: {result}")
    if problems:
        fail(f"{label} cannot do everything calls and samples need: " + "; ".join(problems))


async def kokoro_sample(voice, text):
    audio, rate, width, channels = bytearray(), 24000, 2, 1
    async with AsyncTcpClient(KOKORO_HOST, KOKORO_PORT) as client:
        await client.write_event(Synthesize(text=text, voice=SynthesizeVoice(name=voice)).event())
        while True:
            event = await asyncio.wait_for(client.read_event(), timeout=TIMEOUT_SECONDS)
            if event is None:
                raise RuntimeError("Kokoro closed the connection")
            if AudioStart.is_type(event.type):
                start = AudioStart.from_event(event)
                rate, width, channels = start.rate, start.width, start.channels
            elif AudioChunk.is_type(event.type):
                audio += AudioChunk.from_event(event).audio
            elif AudioStop.is_type(event.type):
                return bytes(audio), rate, width, channels


def clear_old_outbox():
    cutoff = time.time() - OUTBOX_DAYS * 86400
    for entry in os.scandir(OUTBOX):
        with contextlib.suppress(FileNotFoundError):
            if entry.is_file() and entry.stat().st_mtime < cutoff:
                os.remove(entry.path)


def save(stamp, engine, voice, sample):
    audio, rate, width, channels = sample
    path = os.path.join(OUTBOX, f"voice-{engine}-{voice}-{stamp}.wav")
    with wave.open(path, "wb") as file:
        file.setnchannels(channels)
        file.setsampwidth(width)
        file.setframerate(rate)
        file.writeframes(audio)
    return path, len(audio) / (rate * width * channels)


def main():
    if sys.argv[1:] == ["--check"]:
        check()
        return
    chosen = voices(sys.argv[1:])
    text = " ".join(sys.stdin.read().split())
    if not text:
        fail("the line to say goes on stdin, and it was empty", 2)
    if len(text) > MAX_CHARS:
        fail(f"keep the line to {MAX_CHARS} characters, since every OpenAI voice costs money", 2)
    key, label = api_key() if any(v in OPENAI_VOICES for v in chosen) else (None, None)
    os.makedirs(OUTBOX, exist_ok=True)
    clear_old_outbox()
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ") + "-" + secrets.token_hex(2)
    openai_seconds, saved, errors = 0.0, [], {}
    # OpenAI's voices render at once, in the background, while Kokoro, which renders one at a time, works through its own.
    with concurrent.futures.ThreadPoolExecutor(max_workers=MAX_VOICES) as pool:
        pending = {v: pool.submit(openai_sample, key, v, text) for v in chosen if v in OPENAI_VOICES}
        local = {}
        for voice in (v for v in chosen if v not in OPENAI_VOICES):
            try:
                local[voice] = asyncio.run(kokoro_sample(voice, text))
            except (RuntimeError, OSError, asyncio.TimeoutError) as error:
                local[voice] = error
        for voice in chosen:
            engine = "openai" if voice in pending else "kokoro"
            try:
                sample = pending[voice].result() if engine == "openai" else local[voice]
            except RuntimeError as error:
                sample = error
            if isinstance(sample, Exception):
                # One line per distinct reason, naming its voices, so ten identical refusals stay readable.
                errors.setdefault(f"{engine}: {sample}", []).append(voice)
                continue
            path, seconds = save(stamp, engine, voice, sample)
            if engine == "openai":
                openai_seconds += seconds
            saved.append(path)
            print(path)
    cost = openai_seconds / 60 * USD_PER_MINUTE
    summary = f"OpenAI speech: {openai_seconds:.0f} s, about US${cost:.3f}; Kokoro is free."
    print(summary)
    if errors:
        # A failed command shows only its stderr, so the clips that did render are named there too.
        failed = sum(len(v) for v in errors.values())
        for reason, names in errors.items():
            print(f"voice-sample: {', '.join(names)} failed with {reason.split(': ', 1)[0]}: {reason.split(': ', 1)[1]}", file=sys.stderr)
        if any(r.startswith("openai:") for r in errors):
            print(f"voice-sample: the OpenAI voices used {label}", file=sys.stderr)
        for path in saved:
            print(path, file=sys.stderr)
        print(f"voice-sample: {failed} of {len(chosen)} voices failed. {summary}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
