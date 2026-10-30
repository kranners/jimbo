---
name: imagine
description: Generate a picture on the fly with OpenAI's image model, of anything or of Butler himself. Use for "draw me a cat in a spacesuit", "make a poster for Friday's barbecue", "draw yourself on holiday".
---

# Imagine

Use the `imagine` tool, passing the shape as `args` and the prompt as `stdin`, such as `["landscape"]`.
It prints the path of a JPEG in the outbox; attach that path to the reply with the `attach_file` tool.

- `imagine <shape>` draws whatever the prompt describes.
- `imagine butler <shape>` draws Butler, from his own avatar, into the scene the prompt describes.
- The shape is `square`, `portrait` or `landscape`; pick the one that suits the subject, square unless another fits better.

Write the prompt as a full description: subject, setting, style, lighting and mood, in one or two paragraphs.
Ask for any words in the picture in quotes, and keep them short.
A picture takes up to a minute, so say one is coming before calling the tool.
Each picture costs money and sends its prompt to OpenAI, so draw only when Aaron asks for one or a picture plainly says it better than words.
Never put Aaron's private details, such as email, calendar or reminder contents, into a prompt unless he asked for that picture.

When OpenAI refuses a prompt, say so in one line and offer a tamer wording.
When it times out, try once more with a simpler prompt or the `square` shape, then carry on without the picture.
When the tool says there is no OpenAI API key, tell Aaron in one line that `/var/lib/secrets/butler-openai-api-key` needs writing on spike, and carry on without the picture.
