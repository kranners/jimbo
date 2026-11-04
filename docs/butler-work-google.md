# Butler's work mail, calendar and Slack

Butler reads Aaron's work Google Workspace account read-only, as the `mail` account `work` and the `calendar work` views, through `modules/hosts/spike/butler-work-google.nix`.
It holds one OAuth login with two scopes, `gmail.readonly` and `calendar.readonly`, so the token itself cannot send, archive, delete, accept or change anything.
Each call trades the refresh token for an access token kept in memory for that call alone, and nothing read is cached or written anywhere.
The token lives in `/var/lib/butler/.local/share/work-google/token.json`, owner `butler`, mode 600, which butler's own `Read` is denied.

## The ways in, in order

1. **OAuth client in Aaron's own Google Cloud project (built, and the one to try).**
   A desktop OAuth client signs Aaron in as himself, and a Workspace user may grant a third-party app access to his own mailbox unless the work Workspace's admin has restricted unconfigured third-party apps.
   No admin approval is needed when the admin leaves Google's default, "Allow users to access any third-party apps".
   If Google answers "Access blocked: your admin has restricted access", the work Workspace's admin must trust the client ID under Security, API controls, Manage third-party app access, and nothing else here changes.
2. **The calendar's secret iCal address.**
   Calendar only, and Workspace admins turn secret addresses off by default for external sharing, so it most likely needs the admin anyway; not built.
3. **IMAP with an app password.**
   Needs 2-step verification and the admin allowing app passwords and IMAP, gives full read-write mail access rather than read-only, and no calendar; not built, on purpose.
4. **Pilot's screen.**
   Already works: butler can look at Gmail and Calendar in Chromium on `pilot` with `mac pilot`, view only, as the `mac` skill describes.
   It is slow, needs `pilot` awake, and reads only what is on screen.

## What Aaron does once

1. In a Google Cloud project of his own, for example the one butler's Drive login already uses, whose consent screen is published, enable the Gmail API and the Google Calendar API.
   A consent screen left in Testing makes the login expire after 7 days.
2. Under Google Auth Platform, Data access, add the scopes `.../auth/gmail.readonly` and `.../auth/calendar.readonly`, and under Clients create a client of type Desktop app.
3. On spike, run `sudo -u butler butler-work-google-login <work address>`, paste the client ID and secret, open the link it prints in a browser signed in to that work account, allow both permissions, and paste back the `http://127.0.0.1:8976/...` address the browser then fails to load.
   Google warns the app is unverified, since it asks for a restricted scope; that is Aaron's own app, so continue.
4. It checks it signed in as the work address and saves the login; butler uses it from its next call, with no restart.

To take it away, delete that token file on spike, or remove the app under the work account's Google Account, Security, Third-party apps.

## What butler may do with it

- `mail work unread|list|search|read` runs only in a conversation with Aaron, and taints the thread like all mail.
- `calendar work agenda|events` runs in a conversation and on a call, and gives each meeting's time, title, Aaron's response (accepted, tentative or not yet answered; declined ones are left out), attendee count and Meet link, never an attendee's address.
- A scheduled run, such as the morning brief, sees only `calendar work brief`, times and titles, and the work inbox's unread count.
- Its skills tell butler never to copy work mail or meetings into memory, the journal or a change brief, and the work repositories' content stays out of memory as before.

## Slack

The `slack` command already works the moment its token is in place, since it reads `/var/lib/secrets/butler-slack-token` as a systemd credential on every call and says it has no token while the file is empty.

1. At api.slack.com/apps, create an app (or reuse one) in the work Slack workspace, and under OAuth & Permissions add the user token scopes `channels:history`, `channels:read`, `groups:history`, `groups:read`, `im:history`, `im:read`, `mpim:history`, `mpim:read`, `search:read` and `users:read`, and nothing else.
2. Install it to the workspace, which may need a workspace admin's approval if the work admin restricts app installs, and copy the User OAuth Token, starting `xoxp-`.
3. On spike, write it without echoing it: `sudo sh -c 'umask 077; cat > /var/lib/secrets/butler-slack-token'`, paste, then Ctrl-D.
4. Run `sudo systemctl restart butler`, or `/restart` in butler's DM, since systemd copies a credential only when the unit starts.
