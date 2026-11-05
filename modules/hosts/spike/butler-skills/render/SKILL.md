---
name: render
description: Draw calendars, charts, graphs, diagrams and timelines from Aaron's data as a picture to attach. Use for "show me my week", "graph my spending this month", "draw a timeline of the trip", "make a diagram of how this works".
---

# Render

Use the `render` tool, passing the mode and an optional width as `args` and the source as `stdin`, such as `["vega-lite"]` or `["html", "700"]`.
It prints the path of a PNG in the outbox; attach that path to the reply with the `attach_file` tool.

- `render html [width]` screenshots a whole HTML page, for calendars, agendas, tables and anything laid out by hand.
- `render vega-lite [width]` draws a Vega-Lite spec, given as JSON, for line, bar, area, scatter and pie charts; a full Vega spec works too.
- `render mermaid [width]` draws Mermaid source, for flowcharts, sequence diagrams, `gantt` plans and `timeline`s.
- `render svg [width]` draws an SVG you wrote by hand.

The width is in CSS pixels, 1000 unless given, between 320 and 2400; 1000 reads well on a phone, so go wider only for wide charts.
Prefer a picture over a long list whenever the answer is a schedule, a trend or a shape.
Gather the data first with the other tools, then draw it, then say the key point in a line beside the picture.

The page has no network at all, so a web font, a remote image or a fetch fails.
Inline styles in `<style>` and data in the page.
Use your own pictures by reference, in `<img src>`, `srcset`, CSS `url()`, an SVG `<image href>` or a Vega-Lite image mark, rather than pasting them in:

- `asset://<name>` is the asset store's picture of that name, as `asset list` shows it.
- `outbox://<file>` is a picture in the outbox, such as one `imagine` or `mac <host> fetch` just made.
- `mood://<name>` is your mood picture of that mood, such as `mood://content`.
- `scene://<group>/<name>` is a scene picture, such as `scene://general/home`; the `work` ones only in threads about Aaron's work, as when attaching them.

Paths on the page's own origin work too, such as `asset/<name>` or `/mood/content`.
Only pictures load, PNG, JPEG, WebP, GIF, SVG, AVIF, BMP and ICO, at most 25 MB each; `file://`, any other path, `..`, a symlink and the network are refused, and each refusal is printed as a warning naming the address and why, so a broken picture is never silent.
Anything else goes in as a `data:` URI; stdin takes up to 512 KB.
The default look is dark text on white in the system font; set your own colours and sizes for anything more.
In HTML, the globals `vega`, `vegaLite`, `vegaEmbed` and `mermaid` are already loaded.
A `<pre class="mermaid">` element in HTML is drawn before the screenshot.
When HTML draws something asynchronously, set `window.ready` to a promise that settles once it is drawn, such as `window.ready = vegaEmbed("#chart", spec)`.
Only the top 8000 pixels of a tall page are kept, so split a long page into several pictures.
A render gives up after 30 seconds.

For a month calendar, use a seven-column table starting on Monday, with each event as a short coloured label in its day, and today outlined.
Write dates and times the Australian way, day month year and 24-hour or am/pm as Aaron uses them.

When a render fails, the error names the problem, such as a Mermaid parse error with its line; fix the source and try once more.
Look at every picture with Read before attaching it, and fix and render again anything clipped, overlapping or unreadable.
