---
name: backlogic
description: File a new ticket on Aaron's backlogic, the backlog his coding agents work from, named by voice, such as "add a ticket to Jimbo" or "raise a backlogic ticket".
metadata: { "openclaw": { "requires": { "bins": ["backlogic-ticket"] } } }
---

# Backlogic tickets

Use the `backlogic-ticket` command to file tickets on backlogic, the backlog Aaron's coding agents pick work up from, one project per repository.
It can list the projects and their open tickets, and file a new ticket: it cannot edit, answer, close or work a ticket, so never offer to.

- `backlogic-ticket projects` lists every project, one name and its count of open tickets per line.
- `backlogic-ticket tickets <project>` lists the project's open tickets, id and title.
- `backlogic-ticket file <project> "<title>"` files a ticket with its text read from a quoted heredoc, and prints its id:

  ```sh
  backlogic-ticket file jimbo "Short title" <<'EOF'
  The text, in markdown.
  EOF
  ```

  Always pass the text this way, never as a quoted argument.

When Aaron says "issue" he means GitHub, through the `github-issues` skill; when he says "ticket" or "backlogic" he means this one.

## Find the project

Aaron names a project the way he says it, such as "Jimbo" or "Bowerbird", and speech recognition often hears a made-up name as words that sound like it, such as "Bowerberg" for `bowerbird` or "back logic" for `backlogic`.
So run `backlogic-ticket projects` and pick the one whose name sounds like what was heard, ignoring case, spaces and dashes.
If none sounds close, or more than one could, say the closest one or two by name and ask which.

## Gather the ticket

A ticket is worked by an agent that was not in the room, so it needs what is wrong or wanted, and why.
Check `tickets` for an open ticket that already covers it, and if one does, say so and ask whether to file another.
When Aaron's request already says what and why, file it straight away.
Otherwise ask one short question at a time, at most two, then file it with what you have.

Write the title as a short plain sentence of what should change.
Write the text from what Aaron said, in his words where you can, never inventing anything he did not say, and end it with a line saying it was filed by voice from the kitchen panel.
Leave its size and tags to the agent that picks it up.

## Speaking the answer

Say only the project's name and that the ticket is filed, such as "Filed a ticket on Jimbo.", so a wrongly heard project is caught at once.
Never read out the id or the text.
