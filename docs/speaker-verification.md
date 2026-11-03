# Speaker verification on framer

A plan, not yet built, for telling butler whether a voice request came from Aaron.
Asked for on 3 Nov 2026: "could we theoretically train you to only respond to my voice? i'm looking to improve your accuracy."

## What it can and cannot do

Butler receives only text: framer's `wyoming-satellite` streams audio to Home Assistant on spike, `wyoming-faster-whisper-en` transcribes it, Assist answers what its own intents can, and the rest reaches butler's voice endpoint as a chat message.
So the decision has to be made from the audio, before or beside that text, and handed to the daemon as a tag.
A voiceprint makes some answers more convenient for Aaron; it is not security.
A recording of Aaron, the television playing one, or a good imitation can pass it, so nothing it unlocks may be anything a stranger in the kitchen must never get.
It does not improve transcription accuracy: Parakeet hears the same audio either way.
What it can do is refuse or soften answers for anyone else, and let Aaron's own requests reach a little more.

## 1. Model

Use a speaker-embedding model through sherpa-onnx, the runtime spike's recogniser already uses, rather than PyTorch.

- **Recommended: sherpa-onnx's speaker embedding extractor** with `3dspeaker_speech_eres2net_base_sv_en_voxceleb_16k.onnx` or `wespeaker_en_voxceleb_resnet34.onnx` (both about 25 MB, EER around 1% on VoxCeleb1-O), or NeMo's `titanet_small` export (about 40 MB).
  It runs on ONNX Runtime with no PyTorch, takes 16 kHz mono PCM, the format the satellite already records, and returns a fixed-size embedding compared by cosine similarity.
  On framer's i5-7300U one 3 second utterance should embed in roughly 100 to 200 ms; measure before relying on that.
  sherpa-onnx is packaged in nixpkgs (`sherpa-onnx`, with Python bindings); confirm the Python attribute builds against framer's nixpkgs before starting.
- **ECAPA-TDNN through SpeechBrain** (`speechbrain/spkrec-ecapa-voxceleb`) is the best known and about as accurate, but pulls in PyTorch and torchaudio, hundreds of megabytes and a slow import on a laptop that builds nothing itself; use its ONNX export through sherpa-onnx if wanted, not SpeechBrain.
- **Resemblyzer** (GE2E, 2019) is small and easy but measurably less accurate, about 4 to 5% EER, and unmaintained.
- Nothing in the existing pipeline helps: openWakeWord's models detect words, not speakers, and Home Assistant has no speaker-identification feature.

Run it on framer, not spike, so the voiceprint never leaves the panel and the score is computed from the satellite's own capture, before the network.

## 2. Enrolment

- A new command on framer, `voice-enrol`, run over `ssh aaron@framer.local`, records Aaron at the panel through the same PipeWire source, gain and noise suppression the satellite uses, since a voiceprint from another mic scores worse.
  It stops the satellite while recording and starts it again after.
- It prompts for about 30 short phrases, read in a normal voice from where Aaron usually stands: commands like the ones he actually says ("hey butler, what's on today", "add milk to the list") plus some free speech, about 2 to 3 minutes in all, in two or three sessions on different days and times of day if possible, so the print covers morning voice, a busy kitchen and distance.
- It can also take clips from `/var/lib/wyoming-satellite/recordings`, the satellite's own wake recordings, which Aaron confirms are his, the best possible match to real use.
- Each clip is embedded, outliers more than two standard deviations from the mean are dropped, and the rest are averaged and L2-normalised into one voiceprint.
- The voiceprint and the per-clip embeddings go to `/var/lib/speaker-verify/aaron.npy`, owner `aaron`, mode 600, on framer alone: not in git, not in butler's memory, not on spike.
  The raw enrolment audio is deleted once embedded, unless `--keep` is passed for tuning.
- An embedding is not reversible to audio but is biometric data, so it stays off backups that leave the house; `voice-enrol --forget` deletes it.
- Re-enrol whenever the mic, its gain or noise suppression changes.

## 3. Scoring and the tag

### Where the score comes from

- A small service on framer, `speaker-verify`, holds the model and voiceprint in memory and listens on a local socket.
- A fifth `wyoming-satellite` patch, beside the four already in `modules/hosts/framer/voice.nix`, hands it the command's audio, the same chunks it writes to `--debug-recording-dir`, when it sends Home Assistant the end of the audio.
  Only the command after the wake word is scored, never the wake word alone, which is too short and the same words every time.
- The service embeds the utterance, scores it by cosine similarity to the voiceprint, and posts `{score, verified, seconds, at}` to a new local-only Home Assistant webhook, `framer-speaker`, in the background like the satellite's other hooks.
  Home Assistant keeps it in a trigger-based template sensor, `sensor.framer_speaker`, as `framer-voice` does today, and clears it on each wake.
- Utterances under about 1.5 seconds of speech score unreliably and are always `unverified`.

### How it reaches butler

Home Assistant's llama.cpp integration sends only the chat messages and the conversation id, so the tag cannot ride along with the request.
Instead the daemon reads `sensor.framer_speaker` from Home Assistant on `DISCORD_HA_URL`, with the token it already holds once `butler.credentialedTools` is on, at the start of each voice request.
It accepts `verified` only if the sensor's `at` is under 10 seconds old and later than the previous request's, waiting up to 1.5 seconds for a fresh one, since Parakeet takes about half a second and framer's scoring should finish first.
A stale, missing or late score, or Home Assistant not answering, means `unverified`, so every failure falls back to today's behaviour.
In a follow-up turn of the same conversation each utterance is scored afresh; a verified first turn does not verify the rest.

### Threshold

- Start at a cosine score of 0.55 for `verified`, conservative for these models, whose same-speaker scores on clean audio usually sit around 0.6 to 0.8 and different-speaker ones under 0.3.
- Make it `services.speaker-verify.threshold` in the framer module, and log every score, with the transcript's length but not its text, to framer's journal, so it is tuned from real use (see 4).

### The tag

- The daemon adds a third voice lane, `voice-verified`, beside `interactive`, `voice` and `cron` in `LaneSchema` in `src/engine/commands.ts`, chosen per turn from the score, and tells the model in the turn's context: "voice, verified Aaron" or "voice, unverified".
- `unverified` is today's `voice` lane, unchanged: the agenda, unread counts and `Inbox` reminders, nothing private read aloud, nothing sent, no memory changes.
- Every rule in `butler.commands` that names `voice` and no `voice-verified` stays as it is, so nothing widens until a rule names the new lane.
- The daemon's egress gate keeps refusing outbound tools in both voice lanes; `voice-verified` is not `interactive`.

### What a verified tag should unlock

Recommended first step, all read-only and spoken in one or two sentences, because a guest or the television can still be in the room and the print is spoofable:

- Garmin's daily summary, sleep score, Body Battery and steps, and Hevy's next planned workout, read but never changed.
- Unread mail by sender and subject, never the body.
- Adding reminders to any list, not only `Inbox`, and reading a list back.
- `memory-note`, so "remember that ..." lands in butler's journal, which Aaron can read and revert.

Not unlocked, even when verified:

- Any send, email or Messenger, and any Hevy `apply` or `bootstrap`.
  A later step could let a verified voice request queue a send that still waits on Aaron's Approve button in Discord, since the button is the real control; leave that until the first step has run for a few weeks.
- Reading message or mail bodies, Slack, the personal data index, Drive or photos aloud.
- Editing butler's `core` or `skills`, and `change`.

## 4. Failure modes and tuning

- **False accepts** (someone else, or the television, passes): the dangerous direction, kept harmless by unlocking only things above that a stranger overhearing does little with. Raise the threshold if the journal shows non-Aaron scores near it.
- **False rejects** (Aaron fails): the cost is only falling back to today's answers, so the threshold can lean strict. Butler says "I couldn't tell it was you" when an unverified request asks for something the verified lane would allow, so Aaron knows to repeat it closer or check in Discord.
- **Noise** (tap, extractor fan, music): the satellite's noise suppression helps, and enrolment should include some recorded with the usual kitchen noise. Scores drop with signal-to-noise; log the utterance's level beside its score to see it.
- **Distance and the far side of the room**: the Surface's mic picks up more room than voice from a few metres. Enrol from the usual spots, not only up close.
- **A cold, tiredness, a raised voice**: scores drop by perhaps 0.1. Accept the false rejects or re-enrol with a few clips while ill and average them in; do not lower the threshold permanently for it.
- **Short commands**: under about 1.5 seconds they are always unverified, by design.
- **Two people talking**: the embedding averages them and usually fails, which is the safe side.
- **Drift**: once a month or so, `voice-enrol --review` shows the distribution of recent scores from the journal and offers to add recent confirmed-Aaron recordings to the print.
- **Tuning**: after a week, label a sample of the satellite's recordings as Aaron or not, score them offline against the print, and set the threshold where false accepts are near zero, reporting the false reject rate that leaves.
- **Spoofing**: a replayed recording passes. Nothing here prevents it; that is why the tag unlocks only convenience.

## Build order

1. framer: `speaker-verify` service with sherpa-onnx and a chosen model, `voice-enrol`, and the satellite patch, logging scores only, with no webhook yet. Aaron enrols and the threshold is tuned from a week of logs.
2. spike: the `framer-speaker` webhook and `sensor.framer_speaker` in `home-assistant.nix`.
3. claude-discord-threads: the `voice-verified` lane, reading the sensor per voice request, falling back to `voice` on any doubt, with tests for staleness and every failure path.
4. jimbo: rules in `butler-voice.nix` adding `voice-verified` to the commands listed above, a line in `butler-voice.md` on what the tag means, and butler-memory's `core/operating.md` Voice section updated once the daemon emits it.

Nothing is built yet: step 1 needs Aaron at the panel to enrol, and nothing downstream is worth building until real scores show the threshold separates him from the room.
