import argparse
import asyncio
import logging
import os

import numpy
import sherpa_onnx
from sentence_stream import SentenceBoundaryDetector, stream_to_sentences
from wyoming.audio import AudioChunk, AudioStart, AudioStop
from wyoming.event import Event
from wyoming.info import Attribution, Describe, Info, TtsProgram, TtsVoice
from wyoming.server import AsyncEventHandler, AsyncServer
from wyoming.tts import (
    Synthesize,
    SynthesizeChunk,
    SynthesizeStart,
    SynthesizeStop,
    SynthesizeStopped,
)

SPEAKERS = [
    "af_alloy",
    "af_aoede",
    "af_bella",
    "af_heart",
    "af_jessica",
    "af_kore",
    "af_nicole",
    "af_nova",
    "af_river",
    "af_sarah",
    "af_sky",
    "am_adam",
    "am_echo",
    "am_eric",
    "am_fenrir",
    "am_liam",
    "am_michael",
    "am_onyx",
    "am_puck",
    "am_santa",
    "bf_alice",
    "bf_emma",
    "bf_isabella",
    "bf_lily",
    "bm_daniel",
    "bm_fable",
    "bm_george",
    "bm_lewis",
]
WIDTH = 2
CHANNELS = 1
SAMPLES_PER_CHUNK = 1024

KOKORO = Attribution(name="hexgrad", url="https://huggingface.co/hexgrad/Kokoro-82M")

# A request's own `speed`, relative to the server's, which butler's daemon sends for a mood.
MIN_RELATIVE_SPEED = 0.8
MAX_RELATIVE_SPEED = 1.2


def relative_speed(data):
    try:
        speed = float(data.get("speed", 1.0))
    except (TypeError, ValueError):
        return 1.0
    if speed != speed:
        return 1.0
    return min(MAX_RELATIVE_SPEED, max(MIN_RELATIVE_SPEED, speed))


def describe():
    return Info(
        tts=[
            TtsProgram(
                name="kokoro",
                description="Kokoro-82M through sherpa-onnx",
                attribution=Attribution(
                    name="k2-fsa", url="https://github.com/k2-fsa/sherpa-onnx"
                ),
                installed=True,
                version=None,
                supports_synthesize_streaming=True,
                voices=[
                    TtsVoice(
                        name=speaker,
                        description=speaker,
                        attribution=KOKORO,
                        installed=True,
                        version=None,
                        languages=["en_GB" if speaker.startswith("b") else "en_US"],
                    )
                    for speaker in SPEAKERS
                ],
            )
        ]
    )


class Kokoro:
    def __init__(self, model, voice, speed, threads):
        self.tts = sherpa_onnx.OfflineTts(
            sherpa_onnx.OfflineTtsConfig(
                model=sherpa_onnx.OfflineTtsModelConfig(
                    kokoro=sherpa_onnx.OfflineTtsKokoroModelConfig(
                        model=os.path.join(model, "model.onnx"),
                        voices=os.path.join(model, "voices.bin"),
                        tokens=os.path.join(model, "tokens.txt"),
                        data_dir=os.path.join(model, "espeak-ng-data"),
                        lexicon=os.path.join(model, "lexicon-gb-en.txt"),
                        lang="en-GB-x-rp",
                    ),
                    num_threads=threads,
                ),
            )
        )
        self.voice = voice
        self.speed = speed
        self.lock = asyncio.Lock()

    def speaker(self, requested):
        name = requested.name if requested else None
        return SPEAKERS.index(name if name in SPEAKERS else self.voice)

    async def pcm(self, text, speaker, relative=1.0):
        async with self.lock:
            audio = await asyncio.to_thread(
                self.tts.generate, text, sid=speaker, speed=self.speed * relative
            )
        samples = numpy.clip(numpy.asarray(audio.samples), -1.0, 1.0)
        return (samples * 32767).astype("<i2").tobytes()


class Handler(AsyncEventHandler):
    def __init__(self, kokoro, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.kokoro = kokoro
        self.stream = None

    async def handle_event(self, event: Event) -> bool:
        if Describe.is_type(event.type):
            await self.write_event(describe().event())
        elif Synthesize.is_type(event.type):
            if self.stream is None:
                synthesize = Synthesize.from_event(event)
                await self.speak(
                    stream_to_sentences([synthesize.text]),
                    synthesize.voice,
                    always=True,
                    relative=relative_speed(event.data or {}),
                )
        elif SynthesizeStart.is_type(event.type):
            self.stream = SynthesizeStart.from_event(event).voice, SentenceBoundaryDetector()
        elif SynthesizeChunk.is_type(event.type) and self.stream:
            voice, detector = self.stream
            text = SynthesizeChunk.from_event(event).text
            await self.speak(detector.add_chunk(text), voice)
        elif SynthesizeStop.is_type(event.type) and self.stream:
            voice, detector = self.stream
            self.stream = None
            await self.speak([detector.finish()], voice)
            await self.write_event(SynthesizeStopped().event())
        return True

    async def speak(self, sentences, voice, always=False, relative=1.0):
        speaker = self.kokoro.speaker(voice)
        rate = self.kokoro.tts.sample_rate
        started = always
        if always:
            await self.write_event(AudioStart(rate=rate, width=WIDTH, channels=CHANNELS).event())
        for sentence in filter(str.strip, sentences):
            pcm = await self.kokoro.pcm(sentence, speaker, relative)
            if not started:
                started = True
                await self.write_event(
                    AudioStart(rate=rate, width=WIDTH, channels=CHANNELS).event()
                )
            step = SAMPLES_PER_CHUNK * WIDTH * CHANNELS
            for offset in range(0, len(pcm), step):
                await self.write_event(
                    AudioChunk(
                        rate=rate,
                        width=WIDTH,
                        channels=CHANNELS,
                        audio=pcm[offset:offset + step],
                    ).event()
                )
        if started:
            await self.write_event(AudioStop().event())


async def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--uri", required=True)
    parser.add_argument("--model", required=True)
    parser.add_argument("--voice", choices=SPEAKERS, default="bm_lewis")
    parser.add_argument("--speed", type=float, default=1.0)
    parser.add_argument("--threads", type=int, default=4)
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO)

    kokoro = Kokoro(args.model, args.voice, args.speed, args.threads)
    server = AsyncServer.from_uri(args.uri)
    await server.run(lambda *a, **k: Handler(kokoro, *a, **k))


if __name__ == "__main__":
    asyncio.run(main())
