# Issue #156: backlogic on spike's NixOS module behind Caddy

## Found at the start of this session

A prior session had left uncommitted, unpushed changes in this worktree with no
`PROGRESS.md` explaining them (it must have hit its time limit before writing one).
This session picked them up, checked each against the live system, and fixed what
was wrong before committing. What follows is this session's own account.

## Done

- `flake.nix`: added the private `backlogic` input. It must be fetched over SSH
  (`git+ssh://git@github.com/backlogic/backlogic.git`), not `github:`/HTTPS: I
  confirmed by hand that the `backlogic` org's fine-grained-PAT policy refuses
  workaholic's own GitHub token (`403`/`404` on both the REST API and a plain
  `git ls-remote` over HTTPS), and that no SSH key for it exists in this sandbox
  either (confirmed `nix flake check` fails exactly at `Host key verification
  failed` / no key, nothing else — the rest of the flake evaluates cleanly).
- `modules/hosts/spike/backlogic.nix`: the module's `services.backlogic.instances.aaron`,
  Caddy vhost at `backlogic.spike.cute.engineer` (same `reverse_proxy` pattern as
  `monitoring.nix`'s Grafana vhost; no extra firewall rule needed, `caddy.nix`
  already opens `wg0:443` for every vhost). `modules/hosts/spike/default.nix` imports it.
- I read the live `backlogic-aaron` process's actual command line from `/proc` (its
  `--db`, `--port`, `--project`, `--name` flags), since I have no access to
  `systemctl --user` as `aaron` from the `workaholic` user, to pin down the exact
  `dataDir` (`/home/aaron/backlogic-data/aaron`, confirmed) and `project`
  (`bowerbird`, confirmed — I'd wrongly guessed this should be `backlogic` from
  `docs/decisions/mvp.md` and nearly removed it; the live process proved it's
  really `bowerbird`, so I put it back).
- `modules/hosts/spike/CLAUDE.md` and `CHANGELOG.md` describe the change.
- `.github/workflows/test.yml`: **not committed.** The prior session's edit here
  (loading an SSH deploy key from a `BACKLOGIC_DEPLOY_KEY` secret via
  `webfactory/ssh-agent`) is right in shape, but workaholic's GitHub token has no
  `workflow` scope, so pushing a commit touching a workflow file is rejected
  outright (`refusing to allow a Personal Access Token to create or update
  workflow ... without workflow scope`) — discovered only at push time. I backed
  it out of the working tree rather than carry a change that can never be pushed
  from here. **Aaron needs to add this by hand**, in the same step as creating
  the secret itself, right after the `actions/checkout@v4` step:

  ```yaml
      - uses: webfactory/ssh-agent@v0.9.0
        with:
          ssh-private-key: ${{ secrets.BACKLOGIC_DEPLOY_KEY }}
      - run: ssh-keyscan github.com >> ~/.ssh/known_hosts
  ```

## Not done, and why

- **`flake.lock` has no `backlogic` entry.** The prior session had locked it to a
  `path:` input pointing at a local Nix store path it had put the source at by
  some out-of-band means — that only works on this one machine and isn't a real
  fix, so I reverted `flake.lock` and fixed `flake.nix`'s URL instead. Locking the
  real `git+ssh` input needs working SSH access to `backlogic/backlogic`, which
  this sandbox does not have (see above) — **only Aaron can do this**, from a
  machine where his own SSH key already reaches the org. Run `nix flake lock`
  (or just `just check`) there and push the resulting `flake.lock`.
- **CI's `BACKLOGIC_DEPLOY_KEY` secret does not exist yet** on `kranners/jimbo` —
  **Aaron must add it**: a new read-only deploy key on `backlogic/backlogic`,
  its private half pasted in as that repo secret, alongside the workflow edit above.
- **`just check` could not be run to completion in this sandbox or verified in
  CI**, for the same SSH-access reason. Everything else about the flake/module
  evaluates without error (confirmed locally, failing only at the fetch step).
- **Possible peer-sync regression, worth Aaron's attention before switching:**
  the live `backlogic-aaron` process is passed `--peer`, `--peer-url` and
  `--peer-token-file` flags (syncing with Rylee's "Second instance"), but
  `nix/module.nix` in the `backlogic` source this flake input resolves to (from
  the prior session's local copy — I could not re-fetch current `main` to check
  for certain) has no options for any of these, so its `ExecStart` would drop
  them. I also found a live worktree and runner process on spike,
  `~/workspace/backlogic-peer-subscriber--peer-subscriber` running
  `src/runner/main.ts --url http://127.0.0.1:4200`, meaning peer-sync support
  looks to be mid-implementation on backlogic's own side right now. Aaron should
  check whether `backlogic`'s module has grown peer options before switching, and
  if not, extend `modules/hosts/spike/backlogic.nix`'s instance config to pass
  them through, or accept the (hopefully temporary) loss of peer-sync.
- **Stopping the transient `backlogic-aaron` unit** once the module's service is
  confirmed serving the same tickets is a manual step for Aaron
  (`systemctl --user stop backlogic-aaron` as `aaron`) — nothing in this repo
  started that unit, so nothing in it stops it either. `backlogic-runner-aaron`
  is untouched either way, left running, paused.
- **The DNS-only A record** `backlogic.spike.cute.engineer` → `10.100.0.1` in
  Cloudflare — already called out as Aaron-only in the issue body itself.

## Next step

Once Aaron has done the four Aaron-only items above (deploy key secret, flake
lock, peer-sync check, DNS record) and switched spike, confirm
`https://backlogic.spike.cute.engineer/api/snapshot` matches what
`http://spike.local:4200` served before, then stop the transient unit and close
out the issue.
