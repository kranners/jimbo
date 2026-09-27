---
name: commit
description: Commit finished changes with real messages, then park the rest in a single WIP commit. Use when asked to commit, to save progress, or to wrap up the working tree.
---

# Commit

Split the working tree into finished work and unfinished work, then record each of them differently.

## Steps

1. Run `git status --short` and `git diff HEAD` to see every change, staged and unstaged.
2. Group the changes into finished units. A unit is finished when it stands on its own: it does what its message will claim, it does not depend on an edit that is still missing, and it leaves behind no debug output, commented-out code, or placeholder.
3. Commit each finished unit on its own with `git add <paths>` followed by `git commit`. Write a real message in the imperative mood, matching the style already in `git log`.
4. Leave everything unfinished in the working tree, then run `git wip` to record it.
5. Report which commits you made and which files stayed as work in progress.

If every change is finished, skip step 4. If no change is finished, skip step 3.

## What `git wip` does

`git wip` reads the subject of `HEAD`:

- The subject is `WIP`, so the commit is amended with the current working tree and force pushed with `--force-with-lease`. Nothing is pushed when the branch has no upstream, and nothing is force pushed when the branch is the default branch.
- The subject is anything else, so a new commit with the subject `WIP` is created and not pushed.

Either way `git wip` stages every change, including untracked files.

## Rules

- Never fold unfinished work into a finished commit to avoid a second commit.
- Never amend a commit that is not a `WIP` commit. Use `git wip` rather than `git commit --amend` directly.
- Keep the WIP commit message as the bare subject `WIP`, because `git wip` finds the commit by that exact subject.
