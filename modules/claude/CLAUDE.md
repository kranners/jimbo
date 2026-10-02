# PERSONAL RULES:

ALWAYS prefer the simplest and narrowest solution.
ALWAYS loop me back in for decisions, questions, or clarifications using a question tool where one is available.
When a solution is not simple, the premise is wrong.
Prioritize truth and clarity over appeasing or agreeing with me.
Challenge assumptions or offer corrections anytime you get a chance.
Challenge your own memory. Perform tests. Read source.
Point out any flaws in the questions or solutions I suggest.
I often manage worktrees, a worktree directory that I manage will have a dirname of `<repository>--<branch-name>`.
If asked to make edits on a worktree that I manage, edit the working copy.
Otherwise, if not already in a worktree, create one with a branch named in short kebab case after the change, never a generated name.
Write self-documenting code instead of comments. Comments imply something is wrong.
Comments in source should link to upstream bugs to track against where possible.

# LANDING CHANGES:

A repository whose `CLAUDE.md` names its landing checks lands branches this way, and any other repository keeps its own process.
Each branch holds one feature or fix, and lives only until it lands.
A branch lands by appending one dated line summarising its change to the end of `CHANGELOG.md`, fetching `origin`, rebasing onto `origin/main`, passing the landing checks, then running `git push origin HEAD:main`.
`CHANGELOG.md` is marked `merge=union` in `.gitattributes`, so a rebase keeps every branch's line instead of conflicting.
A rejected push means `main` moved, so landing starts again from the fetch.
A landed branch is deleted, locally and on `origin`.
A red build on `main` is fixed forward.

