# Butler's messaging: reading and writing Slack, Messenger, Discord and Google Chat

Aaron asked on 7 Nov 2026 for Butler to have full read and write on his Discord, Messenger, Google Chat and Slack, with every outbound message gated by his approval exactly like `mail-send` and reads left free.
This is what each has, what it needs from him, and the gaps nearby.

## The gate every send shares

A send is a command rule that taints the thread, goes out and is the fixed outcome `message` to the recipient argument, as `mail-send`'s is, so outside a mission that names that recipient the daemon shows Aaron the exact command, recipient and text and waits for his Approve, a scheduled run's send included, and a voice request never sends.
Each sender refuses text its approval could not show whole, so what he approves is what goes.
The screen route (`mac` on `piggys-MBP`) is gated the same way by `mac`'s outcome checker: Return, a typed newline, a click or a press in a messaging app or a chat or mail page is refused until Butler runs it as `mac <host> confirm "send '<text>' to <person> in <app>" …`, whose button shows that sentence.
Butler's own browser is not gated, since its tools never ask, so the skills keep sends out of it.
Every send is logged to `audit/<command>` in butler's memory with its recipient and text, `audit/mac` for the screen route.

## Slack, the work workspace

- Reads: `slack`, unchanged.
- Writes: `slack-send post | reply | react | edit | delete`, to `#channel`, `@handle` or `@a,@b`, never a bare id, so the approval names who it goes to, edits and deletes limited to messages it posted, at most about 500 characters so every approval card shows it whole, at most 20 writes an hour (`modules/hosts/spike/butler-slack.nix`, `butler-slack/send.py`).
- It writes with a token of its own, `/var/lib/secrets/butler-slack-write-token`, loaded by `slack-send` alone, so the reader and the chat sync, which run without asking, never hold a token that can write, and `butler-slack-login` refuses a reader's token with write scopes.
- Aaron makes a second Slack app for it: api.slack.com/apps, Create New App, From scratch, in the work workspace, then OAuth & Permissions, User Token Scopes, adding `chat:write`, `reactions:write`, `im:write`, `mpim:write`, `groups:write`, `channels:read`, `groups:read`, `im:read`, `mpim:read` and `users:read`, then Install to Workspace (the workspace's admin may need to approve it), copies the User OAuth Token, and on spike runs `sudo butler-slack-login --write`, pasting it hidden.
  Butler may click through those pages for him under a mission naming them, as on 6 Nov 2026, but only Aaron pastes the token.

## Messenger

- Reads `messenger-chats` and `messenger-read`, send `messenger-send`, through the mautrix-meta bridge, now switched on (`butler.messenger.enable`).
- The bridge's Facebook login lapsed on 5 Nov 2026: Facebook answered it 401 and has redirected it to its login page since, so until Aaron runs `sudo messenger-setup` on spike and logs in again (`login messenger-lite-android`, email or phone, password, two-factor code, then the secure storage PIN or `skip`), reads show only the history the bridge kept before 5 Nov and every send is refused.
- `messenger-send` now waits for the bridge's delivery status, so a send while logged out says Messenger refused it instead of claiming it went.
- Fragile: Meta forbids puppeting an account, may ask for a captcha or password reset after unusual activity, ends sessions without warning, as on 5 Nov, and changes its protocol, after which the bridge needs a nixpkgs bump within days.
  The bridge holds its own Facebook session, apart from Butler's browser, so logging in to Facebook in the browser does not fix it.

## Google Chat

- The Google Chat API serves Google Workspace accounts alone: a personal Google account can neither call it with its own login nor host a Chat app, so there is no API route for Aaron's personal Chat.
- Takeout exports Chat's history, which the index already reads as `chat`'s Google Chat source.
- The route that works is the screen: `chat.google.com`, or Chat in Gmail, in Chromium on `piggys-MBP`, read by looking and sent through `mac … confirm`, which now counts any page titled with Chat as a sending page.
- Not built: driving `chat.google.com` in Butler's own browser, since its sends would be ungated.

## Discord

- Automating Aaron's own account with his user token, a self-bot, breaks Discord's terms and risks his account being banned, so it is not built.
- Bots are allowed, but only in servers someone with Manage Server adds them to, and no bot can read or send in a DM between people or join a group DM.
- Built: the screen route, the Discord app on `piggys-MBP` through `mac … confirm`, recipe in the mac skill, which reads and sends anywhere Aaron can, DMs included, as him on his own screen.
- Not built, a decision for Aaron: a `discord-send` and `discord-read` through Butler's own bot in servers he chooses to add it to, which would post as Butler, not as him, and needs a list of those servers.

## `chat send`

Not built: each sender's approval names its own recipient argument, and a router would put every send under one command whose approval reads differently from the tool that sends, so Butler calls `slack-send`, `messenger-send` or `mac … confirm` directly.

## Gaps nearby, most valuable first

1. Messenger's login, a hand step today, then nothing else.
2. Mail: archive from the inbox is all it changes; marking read, moving, labelling and deleting, each an `acts` rule, deletes gated like `delete`.
3. Slack write scopes, a hand step today.
4. GitHub: issue create only; comments, PR reviews and replies, gated as `publish`.
5. iMessage and SMS sends: screen route only; a `messages-send` through AppleScript on `piggys-MBP`, gated like `messenger-send`.
6. Reminders edit and delete, covered by another change with the calendar.
7. Contacts: read only, from memory's contacts map.
8. Drive: read only; uploads and edits, gated as `upload`.
9. Instagram and LinkedIn sends: screen route only, and both forbid automation, so it stays that way.

## Memory edits for Butler to make

- `core/operating.md`, the Slack line: "`slack` reads it and `slack-send` posts, replies, reacts and edits or deletes its own messages, each write after Aaron approves the exact channel and text; the slack and slack-send skills."
- `core/operating.md`, add: "**Discord, Google Chat, iMessage, Instagram, LinkedIn**: no command sends; read and send on `piggys-MBP`'s screen with `mac … confirm`, the mac skill's section on them; never from my own browser."
- `skills/messenger/SKILL.md`: say the bridge holds its own Facebook login, apart from my browser's, that it lapsed on 5 Nov 2026 and needs `sudo messenger-setup`, and that a send now reports delivered, refused or unconfirmed.
- `skills/contacts`: note each person's Slack handle where known, so `slack-send post @handle` reaches them.
