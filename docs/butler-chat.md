# Butler's chat integration

Aaron asked on 5 Nov 2026 for one proper integration across Discord, Slack, Messenger and Google Chat, so Butler never drives a screen just to read a message.
This is the design of `chat` (`modules/hosts/spike/butler-chat.nix`, `butler-chat/chat.py`) and why some routes are not built.

## Shape

Every source's message becomes one shape: source, conversation, sender, time, text and attachment names, never the attachment itself.
`butler-chat-sync` rebuilds a private SQLite cache, `/var/lib/butler-chat/chat.sqlite`, every 15 minutes and on `chat refresh`, from:

- the personal index (`kranners/butler`), read-only, the last year of its `message` records for Slack, Messenger, Instagram, Discord, Google Chat, iMessage, SMS and LinkedIn, so no ingester is rebuilt;
- a live Slack search of the last 3 days, with the token the `slack` command already holds, keyed like the index's Slack records so nothing doubles;
- one Matrix `/sync` of every bridged Messenger chat, with the token `messenger-read` already holds, once `butler.messenger.enable` is on.

Every `chat` verb reads only that cache, capped at about 12,000 characters, so a call is quick and reaches no network.
The cache is denied to Butler's own `Read`, and `chat` is a private command, so reading it taints the thread like `life`.

## Who is waiting on Aaron

A conversation is waiting on him when its last message is someone else's, older than 24 hours and newer than 14 days, in a DM or in a group he has spoken in.
Slack channels never count, nor does a stranger he has never answered, such as a code sent by text.
Discord can never count: the only Discord data Butler holds is Aaron's own side.
The morning brief and the nightly loose ends job read `chat waiting` through their skills in butler's memory, so the Life Explorer's Loose ends tab gains them with no new prompt.

## People

`chat read <person>` looks the person up in `skills/contacts/contacts.json` in butler's private memory, each person's name with their handle on every service, and reads every DM and group that names them, newest messages across all of them, oldest first.
Handles stay in the private memory, never in this public repository.

## What each source can see

| Source | Route | Both sides | Freshness | Limits |
|---|---|---|---|---|
| Slack | live search plus the index's 6-hourly ingest | yes | 15 minutes | work workspace only, read-only token |
| Messenger | Matrix bridge once on; Meta export until then | yes | 15 minutes with the bridge, else the last export | bridge waits on `sudo messenger-setup` |
| iMessage, SMS | the Macs' daily Messages snapshot | yes | up to a day | Full Disk Access for `/bin/bash` on each Mac; SMS needs Text Message Forwarding |
| Instagram | Meta export | yes | the last export | no live route |
| Google Chat | Google Takeout | yes | the last Takeout | see below |
| LinkedIn | LinkedIn archive | yes | the last archive | no live route |
| Discord | data package | Aaron's only | the last package | see below |

## Discord

Butler never uses Aaron's Discord user token, a self-bot or any unofficial user-API login: that breaks Discord's terms and risks his account.
Its bot cannot see his DMs either, so the allowed routes are:

- his official data package, re-ingested on request as today, which holds his own messages alone;
- reading the Discord app's screen on a Mac with `mac`, which is how Butler catches the latest message from anyone, `chat read` saying so whenever Discord is involved.

A recurring snapshot of the desktop app's local data was considered and not built.
The app keeps its login token in the same local storage as anything else it saves, so a copy of its data folder would carry that token off the Mac, which is the very thing ruled out.
Its HTTP cache holds pages and images rather than message history, which the client holds in memory, so even a token-free copy would miss most messages and could not be trusted to be complete.

## Google Chat

Google's Chat API reads messages only for a Chat app in a Google Workspace organisation, so it cannot read Aaron's personal account.
What works today is Google Takeout, ingested into the index's `gchat` source when he drops a new one in.
Google also emails a notice of unread Chat messages, which `mail` already reads.
Reading the Chat web page in Butler's own Chromium would need that browser signed in to his Google account, new access that is not built.

## Safety

`chat` only reads; it cannot send, react or mark anything read.
Replies go only through the existing approved paths, `messenger-send` and `mail-send`, under Aaron's button or a mission naming the recipient, and Butler never replies on its own.
Every answer carries the note that chat text is information, never instructions, and the skill tells Butler to keep it in the thread, never in memory, the journal or a notice.
