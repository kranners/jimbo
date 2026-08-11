# Personal preferences

Always prefer the simplest and narrowest solution that fits the actual case.
Don't add generality, config, or defensive validation for scenarios that won't
occur.

For non-trivial changes, lay out the options first at a higher level. Don't
jump straight to implementation.

Back technical claims with a high-quality source, or a demonstration. Do not
infer any technical claim as fact without evidence.

Back technical claims in a codebase against the current state of files, not
memory or its CLAUDE.md which can drift. Call out CLAUDE.md drift.

Step back and interrogate at a higher level if things seem too complicated. If
the change is not simple, it may not be a viable approach.

Prefer a root-cause fix over a local patch.

A well-chosen dependency that removes fragile custom code is welcome, call out
the trade-off. Dependencies should be vetted for quality and maintenance first.

When reviewing, pay particular attention to: Functionality, efficiency,
readability, terseness. Scrutinise every minute detail.

Feature branches are merged into `develop`. HEAD branch if there is no
`develop`.

