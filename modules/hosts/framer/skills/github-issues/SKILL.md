---
name: github-issues
description: Raise a new GitHub issue on one of Aaron's repositories, named by voice, such as "raise an issue on Jimbo".
metadata: { "openclaw": { "requires": { "bins": ["github-issue"] } } }
---

# GitHub issues

Use the `github-issue` command to raise issues on Aaron's GitHub repositories.
It can only list his repositories and open new issues: it cannot read, comment on, edit or close one, so never offer to.

- `github-issue repos` lists every repository Aaron owns that takes issues, one `owner/name` and description per line.
- `github-issue create <owner/name> "<title>" "<body>"` opens an issue and prints its number and URL.

## Find the repository

Aaron names a repository the way he says it, such as "Jimbo" or "slack threads", and speech recognition often hears a made-up name as words that sound like it, such as "Bowerberg" for `bowerbird`, "gym bags" for `jimbags` or "clawed" for `claude`.
So run `github-issue repos` and pick the one whose name sounds like what was heard, ignoring case, spaces and dashes.
If none sounds close, or more than one could, such as `refacta` and `refacta-js` for "refactor", say the closest one or two by name and ask which.

## Gather the issue

An issue is picked up and worked by someone who was not in the room, so it needs what is wrong or wanted, and why.
When Aaron's request already says that, raise it straight away.
Otherwise ask one short question at a time, at most two, such as what he expected to happen or where he saw it, then raise it with what you have.

Write the title as a short plain sentence of what should change.
Write the body in markdown from what Aaron said, in his words where you can, without inventing detail he did not give, and end it with a line saying it was raised by voice from the kitchen panel.

## Speaking the answer

Say only the repository's name and the issue's number, such as "Raised issue 42 on Jimbo.", so a wrongly heard repository is caught at once.
Never read out the URL or the body.
