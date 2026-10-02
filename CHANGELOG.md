# Changelog

- 2026-10-03: The landing workflow moves into the personal `CLAUDE.md`, and each landed change appends one line here.
- 2026-10-03: spike runs `discord-threads.service`, giving each Discord thread its own Claude Code session through the Nix-managed `claude`.
- 2026-10-03: Claude Code enables experimental agent teams through `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` in the shared `settings.json`.
- 2026-10-03: claude-discord-threads moves to a private repository that spike pulls with a read-only deploy key, and `/done` cleans up a thread's worktree.
