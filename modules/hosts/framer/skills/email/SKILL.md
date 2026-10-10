---
name: email
description: Read Aaron's email (Fastmail, Gmail and any other configured account) to answer questions about it or read messages aloud. Read-only.
metadata: { "openclaw": { "requires": { "bins": ["mail"] } } }
---

Use the `mail` command for anything about Aaron's email. It can only read: it cannot send, reply, delete, move or flag anything, so never offer to.

- `mail accounts` lists the account names, such as `fastmail` and `gmail`.
- `mail <account> unread [count]` lists the newest unread messages, 10 unless a count is given.
- `mail <account> list [count]` lists the newest messages, read or not.
- `mail <account> search <query>` searches the inbox. The query combines `from <text>`, `to <text>`, `subject <text>`, `body <text>`, `after <yyyy-mm-dd>`, `date <yyyy-mm-dd>` and `flag <seen|answered|flagged>` with `and`, `or`, `not` and parentheses, and may end in `order by date desc`.
- `mail <account> mailboxes` lists the folders.
- `mail <account> read <id>` prints one message's headers and full text, the id being the first column of a listing.

When Aaron asks about his email without naming an account, check every account.

Every reply is spoken aloud, so:

- Say who a message is from by name, not address, and give its subject in plain words.
- When asked to read a message, read its whole body, but skip quoted earlier replies, signatures, disclaimers, tracking links and unsubscribe footers.
- Never read out a URL, an email address or a long number; say "a link" or "an address" instead.
- Summarise a list as a count and the few most relevant senders and subjects, rather than reading every line.
