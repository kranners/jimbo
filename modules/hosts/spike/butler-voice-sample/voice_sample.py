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
EX_TEMPFAIL = 75

USAGE = f"""usage: voice-sample [voice...]   (the line to say on stdin, at most {MAX_CHARS} characters)
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
    directory = os.environ.get("CREDENTIALS_DIRECTORY")
    try:
        with open(os.path.join(directory or "", "openai-api-key")) as file:
            return file.read().strip()
    except (OSError, TypeError):
        fail("no OpenAI API key: the openai-api-key credential is missing")


def openai_sample(key, voice, text):
    try:
        response = requests.post(
            SPEECH_API,
            headers={"Authorization": f"Bearer {key}"},
            json={"model": SPEECH_MODEL, "voice": voice, "input": text, "instructions": style(), "response_format": "pcm"},
            timeout=TIMEOUT_SECONDS,
        )
    except requests.RequestException as error:
        raise RuntimeError(f"could not reach OpenAI: {type(error).__name__}")
    if not response.ok:
        try:
            message = response.json()["error"]["message"]
        except (ValueError, KeyError, TypeError):
            message = response.text[:200]
        raise RuntimeError(f"OpenAI refused (HTTP {response.status_code}): {message}".replace("\n", " "))
    # 24 kHz mono 16-bit PCM.
    return response.content, 24000, 2, 1


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
    chosen = voices(sys.argv[1:])
    text = " ".join(sys.stdin.read().split())
    if not text:
        fail("the line to say goes on stdin, and it was empty", 2)
    if len(text) > MAX_CHARS:
        fail(f"keep the line to {MAX_CHARS} characters, since every OpenAI voice costs money", 2)
    key = api_key() if any(v in OPENAI_VOICES for v in chosen) else None
    os.makedirs(OUTBOX, exist_ok=True)
    clear_old_outbox()
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ") + "-" + secrets.token_hex(2)
    openai_seconds, failures = 0.0, 0
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
                failures += 1
                print(f"voice-sample: {engine} {voice} failed: {sample}", file=sys.stderr)
                continue
            path, seconds = save(stamp, engine, voice, sample)
            if engine == "openai":
                openai_seconds += seconds
            print(path)
    cost = openai_seconds / 60 * USD_PER_MINUTE
    print(f"OpenAI speech: {openai_seconds:.0f} s, about US${cost:.3f}; Kokoro is free.")
    if failures == len(chosen):
        sys.exit(EX_TEMPFAIL)


if __name__ == "__main__":
    main()
