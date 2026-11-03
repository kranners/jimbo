---
name: voice-sample
description: Audition voices for Butler's calls: say one line in several OpenAI and Kokoro voices and attach the clips, so Aaron can pick his voice. Use for "let me hear some voices", "try a different voice", "what would you sound like as ...".
---

# Voice samples

Use the `voice-sample` tool, with the voices as `args` and one short line on `stdin`.
With no `args` it renders every OpenAI realtime voice, `alloy`, `ash`, `ballad`, `cedar`, `coral`, `echo`, `marin`, `sage`, `shimmer` and `verse`, read with Butler's voice brief, plus Kokoro's British `bm_george`, `bm_lewis`, `bm_daniel` and `bm_fable`; `openai` or `kokoro` picks one set, and any single name picks that voice.
It prints one WAV path per voice, each named `voice-<engine>-<voice>-…`, then the OpenAI cost; attach every path with `attach_file`, and list the voices in the same order so Aaron can say which he liked.

Write the line in Butler's own manner, dry and warm, one or two sentences of about 20 words, such as "Good evening, sir. I've taken the liberty of moving your dentist to Thursday; you seemed so attached to Tuesday's nap."
Every OpenAI voice costs about a cent for a short line, so keep the line short and render a set only when Aaron asks to hear voices.
Never put his private details in the line.

Do not pick a voice for him.
Once he picks one, tell him to send `/realtime voice <name>` for an OpenAI voice, which calls use from the next call, or `/realtime kokoro <name>` for the ordinary Kokoro voice, used when the realtime voice is off or gives up; `/realtime` shows both, and `default` goes back to the configured voice.
On a call, the realtime voice also follows the voice brief these samples are read with, so the call sounds like the sample.
When a Kokoro voice fails, the local speech server on spike is down; say so and send the rest.
