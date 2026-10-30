---
name: backlogic
description: File a new ticket on Aaron's backlogic, the backlog his coding agents work from, such as "add a ticket to jimbo" or "raise a backlogic ticket", or check a project's open tickets.
---

# Backlogic tickets

Use the `backlogic-ticket` tool, passing the words after `backlogic-ticket` as `args`, such as `["tickets", "jimbo"]`.
Backlogic is the backlog Aaron's coding agents pick work up from, one project per repository.
The tool can list the projects and their open tickets, and file a new ticket: it cannot edit, answer, close or work a ticket, so never offer to.

- `backlogic-ticket projects` lists every project, one name and its count of open tickets per line.
- `backlogic-ticket tickets <project>` lists the project's open tickets, id and title.
- `backlogic-ticket file <project> <title>` files a ticket with its markdown text as `stdin`, and prints its id.

When Aaron says "issue" he means GitHub, through the `github-issues` skill; when he says "ticket" or "backlogic" he means this one.

## Find the project

Run `backlogic-ticket projects` and pick the one Aaron named, ignoring case, spaces and dashes.
If none matches, or more than one could, name the closest one or two and ask which.

## Gather the ticket

A ticket is worked by an agent that was not in the conversation, so it needs what is wrong or wanted, and why.
Check `tickets` for an open ticket that already covers it, and if one does, say so and ask whether to file another.
When Aaron's request already says what and why, file it straight away.
Otherwise ask one short question at a time, at most two, then file it with what you have.

Write the title as a short plain sentence of what should change.
Write the text from what Aaron said, in his words where you can, never inventing anything he did not say, and end it with a line saying it was filed through Butler on Discord.
Leave its size and tags to the agent that picks it up.
Every ticket is assigned to Aaron, so it waits on the board until he hands it to an agent.

## Answering

Reply with the project and that the ticket is filed, such as "Filed a ticket on jimbo", and nothing more.
