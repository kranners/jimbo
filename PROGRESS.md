# Issue #152: Two tables on the Workaholic and threads dashboard

## Status: done, pushed for review

## What was done

- `modules/hosts/spike/dashboards.nix`: added two full-width table panels at the top of
  the `agents` ("Spike / Workaholic and threads") dashboard, and set its `refresh` to `30s`.
  - **Issues by state**: one GitHub query (`is:open`, `timeFrom = "10y"`), columns
    state/repo/number/title/preview/updated. State is computed (not just a display mapping)
    because Grafana's table always sorts by a field's *raw* value, never its mapped display
    text (confirmed by reading `TableNG/utils.ts` in grafana/grafana — `applySort` reads
    `frame.fields[...].values` directly), so a value mapping alone can't drive row order.
    The pipeline: `extractFields` (one regex, one independent lookahead per state label) →
    `convertFieldType` to boolean → one `calculateField` (binary multiply) per label, weighted
    by powers of two in pick order (8/4/2/1) → one `calculateField` (reduceRow sum) into `rank`
    → `calculateField` for `preview` (`number + 4000`) → `organize` (exclude helper/unwanted
    fields, order columns, rename `rank`→`state`, `updated_at`→`updated`) → `sortBy` desc on
    `state`. A field override on `state` holds the range-type value mappings (one range per
    weight, `[weight, weight*2-1]`, so any lower-ranked labels present can't push a row out of
    its highest-ranked bucket) with the colours. `title` and `preview` get `links` overrides
    using `${__data.fields.repo}`/`${__data.fields.number}`/`${__data.fields.preview}`.
  - **Live sessions**: instant Prometheus table, `count by (job, session_id, issue)
    (claude_code_session_count_total)` merged with `sum by (job, session_id, issue)
    (rate(claude_code_active_time_seconds_total[$__rate_interval]))`. `extractFields` splits
    the `issue` label (`owner/repo#number`) into hidden `repo`/`number` fields (`custom.hideFrom.viz`
    override, not excluded, so the link template can still read them) for the `issue` column's
    link. `working` gets a value mapping: `null+nan`/`0` → idle (grey), anything else → working
    (green).
  - `.claude/CLAUDE.md` (root one — the detailed Grafana/dashboard sentences live there, not
    in `modules/hosts/spike/CLAUDE.md`, which is just spike's short per-session preamble):
    added two sentences describing the new tables, right after the existing
    "reads closed without change..." sentence.

## Verification done

- `just check` (`nix flake check --show-trace`) passes.
- Built the `grafana-dashboards` linkFarm derivation directly (`nix-store -r` on its drvPath)
  and inspected the generated `agents.json` with `jq` to confirm the panel JSON, transformation
  pipeline, field overrides and `refresh: "30s"` all serialize as intended.
- Verified field/plugin semantics against source rather than guessing:
  - `grafana/github-datasource` (installed plugin version 2.9.1, matches `main` branch's
    `pkg/github/issues.go`): the `repo` field is always `Repository.NameWithOwner`
    (`owner/name`, never bare), and `labels` is a JSON array string (`json.RawMessage` of
    `json.Marshal([]string)`), not a joined string. So the "repo may be bare" and "labels may
    be joined" hedges in the issue text don't apply to this plugin version — only the JSON
    array form.
  - Grafana core transforms (`calculateField`, `extractFields`, `convertFieldType`, `organize`,
    `sortBy`, value mappings) checked against `grafana/grafana` main branch source (matches
    installed Grafana 13.1.6 closely enough; none of the relevant code looked version-skewed)
    for exact option shapes (e.g. `BinaryValue.fixed`/`.matcher`, `ReduceOptions.include`,
    `RangeMapOptions.from/to`, the `custom.hideFrom.viz` table field override path).
  - Confirmed via source that `sortBy`'s `options.sort` only honours its *first* entry today
    (comment in `sortBy.ts`: multi-sort isn't implemented), which is why state needed a single
    combined numeric rank rather than a multi-key sort across four boolean flags.
- Could **not** test this against the live dashboard in a browser: no Grafana admin/API
  credentials are reachable from this worktree (running as the `workaholic` user; admin
  credentials and the GitHub datasource token file are root/`grafana`-owned and not meant to
  be readable from here). Visual verification on spike happens after this branch lands and
  someone runs `git pull && just` there, per this repo's own CLAUDE.md.

## Open follow-up (not a blocker for landing)

- `kranners/workaholic#24` (tagging session telemetry with the `issue` resource attribute) is
  **open** but not a blocker: the issue's own text anticipates this ("it is filled once
  kranners/workaholic#24 lands and empty for slack-threads and discord-threads rows"). Until
  it lands and spike picks it up, the "Live sessions" table's `issue` column will be empty for
  every row, including workaholic's own — that's expected, not a bug in this change.

## Nothing left to do here

Everything in the issue's "Done when" list that can be checked without a live Grafana session
is done. The remaining checks (visual confirmation on spike over WireGuard) need Aaron (or a
switch) after this lands.
