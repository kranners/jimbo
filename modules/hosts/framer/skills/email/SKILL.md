---
name: email
description: Read Aaron's email (Fastmail, Gmail and any other configured account) to answer questions about it, read messages aloud, or archive them.
metadata: { "openclaw": { "requires": { "bins": ["mail"] } } }
---

Use the `mail` command for anything about Aaron's email. It can read and archive: it cannot send, reply, delete, flag or move a message anywhere but its account's archive, so never offer to.

- `mail unread-counts` prints every account's number of unread messages in one go; use it for any question about how much unread mail there is.
- `mail accounts` lists the account names, such as `fastmail` and `gmail`.
- `mail <account> unread [count]` lists the newest unread messages, 10 unless a count is given.
- `mail <account> list [count]` lists the newest messages, read or not.
- `mail <account> search <query>` searches the inbox. The query combines `from <text>`, `to <text>`, `subject <text>`, `body <text>`, `after <yyyy-mm-dd>`, `date <yyyy-mm-dd>` and `flag <seen|answered|flagged>` with `and`, `or`, `not` and parentheses, and may end in `order by date desc`.
- `mail <account> mailboxes` lists the folders.
- `mail <account> read <id>` prints one message's headers and full text, the id being the first column of a listing.
- `mail <account> archive <id>...` moves messages out of the inbox into the account's archive, the same as archiving them in its own app.

Archive only messages Aaron has asked to archive, such as "archive that" after reading one or "archive everything from the newsletter", listing first to find their ids, then say in one sentence how many were archived and from whom.

When Aaron asks about his email without naming an account, check every account.

Every reply is spoken aloud, so:

- Say who a message is from by name, not address, and give its subject in plain words.
- When asked to read a message, read its whole body, but skip quoted earlier replies, signatures, disclaimers, tracking links and unsubscribe footers.
- Never read out a URL, an email address or a long number; say "a link" or "an address" instead.
- Summarise a list as a count and the few most relevant senders and subjects, rather than reading every line.
