# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Nix flake configuring five machines for a single user (`aaron`, `aaronpierce` on the second MacBook):

- `jimbo`, NixOS PC, `x86_64-linux`
- `piggys-MBP`, MacBook via nix-darwin, `aarch64-darwin`
- `pilot`, second MacBook via nix-darwin, `aarch64-darwin`, same setup as `piggys-MBP` plus the tooling its work repositories expect (`modules/hosts/pilot/work-tools.nix`), its computer and network names set to `pilot` by nix-darwin
- `spike`, always-on NixOS box, `x86_64-linux`
- `framer`, NixOS Surface Book 2 laptop, `x86_64-linux`

## Commands

```sh
just          # rebuild + switch the current host (runs `git add .` first, then nh)
just check    # nix flake check --show-trace
```

`just` stages everything before building because flakes only see git-tracked files.

## Workflow

The landing check is `just check`.
The weekly `flake-update-*` branches are the exception: they land through the pull request the bot opens.
CI runs `nix flake check` on every push to every branch (`.github/workflows/test.yml`).
The weekly update bumps every input.
It also runs `modules/browser/update-extensions.sh`, which pins each browser extension in `modules/browser/extensions.nix` to the release the Chrome Web Store serves, since the store serves only the newest one and an older pin fails the build.
The flake check `browser-extensions` fetches every pinned extension, so CI's `cachix watch-store` pushes each one to the `kranners` cache, from which every host substitutes it after the store has moved on, so a pin that lags the store still builds.
`.claude/worktrees/` is gitignored so the `git add .` in `just` never stages a worktree.

Update this file, or `modules/hosts/spike/CLAUDE.md`, in the same branch as any change that makes it wrong.
It keeps one sentence per line, so git merges edits from two branches sentence by sentence.

## Architecture

Instead of writing `nixosConfigurations`/`darwinConfigurations` directly, `flake.nix` runs `lib.evalModules` over `./modules` once per host and merges the results with `lib.recursiveUpdate`.

Every directory under `modules/` is a config module that contributes to one or more of these options (defined in `modules/default.nix`):

- `sharedSystemModule` / `sharedHomeModule` — both platforms
- `nixosSystemModule` / `nixosHomeModule` — Linux only
- `darwinSystemModule` / `darwinHomeModule` — macOS only

`modules/default.nix` assembles these into the real `nixosConfigurations`/`darwinConfigurations` (guarded by platform, parsed from `host.system`).
`modules/home/default.nix` wires the home modules into home-manager for `host.username`.

`modules/default.nix` imports its first list of modules on every host, its second list only when `host.desktop` is true, and a third list, after the desktop one, only when `host.kiosk` is true, for a machine that runs as an appliance instead of a desktop.

**To add configuration:** create `modules/<name>/default.nix` returning an attrset with the relevant option keys above, and add `./<name>` to the `imports` list in `modules/default.nix`, in the `host.desktop` list if it only makes sense on a machine with a screen, or the `host.kiosk` list if it only makes sense on an appliance.

Modules receive `inputs` (flake inputs) and `host` (`{ system, hostname, username, desktop, kiosk }`) via `specialArgs`, in addition to the usual `pkgs`/`lib`/`config`.
Because `host` is a `specialArg`, `imports` may depend on it, whereas depending on `config` there recurses infinitely.

### Hosts

`modules/hosts/<host>/` holds facts about one machine only: hardware, bootloader, hostname, state versions.
Only the directory named exactly `host.hostname` is imported, so it applies to that machine alone.

### spike

`spike` is headless (`desktop = false`), so it gets the shared modules and home-manager but none of the desktop ones.
Its files under `modules/hosts/spike` are plain NixOS modules, imported through `nixosSystemModule`.
`modules/hosts/spike/CLAUDE.md` is appended to the personal `CLAUDE.md` on spike alone, so every Claude Code session there knows it is on production and how the host is run.

- SSH: `ssh aaron@spike.local` (key auth, resolved over mDNS).
- The repo is cloned at `~/workspace/jimbo` on `main`.
  To deploy, push to `main`; `jimbo-switch.timer` pulls and switches spike within 5 minutes, or run `git pull && just` there at once.
- SSH accepts keys only, declared in `modules/hosts/spike`.
  Rylee logs in as `rylee` from her laptop, noodlebook, in `wheel` and `docker` like `aaron`.
  `sudo` is passwordless (`wheelNeedsPassword = false`), so run the deploy over SSH directly.
- Headless. Docker is managed directly with `docker`/`docker compose`; `aaron` is in the `docker` group.
  `docker-prune.timer` runs `docker system prune --all --filter until=24h` daily, removing stopped containers, unused networks, every image no container uses and build cache once each is a day old, because rebuilding backlogic's image leaves the previous one and its cache behind; volumes, Bowerbird's named Postgres one among them, and images a container uses are kept.
- Grafana listens on `127.0.0.1:3001`, backed by Prometheus scraping node_exporter and cAdvisor.
  Caddy serves it at `https://grafana.spike.cute.engineer`, whose DNS-only A record points at `10.100.0.1`, so it is reached over WireGuard alone.
  Its dashboards, Hardware, Services, Containers, Claude, and Backlogic, are provisioned from `modules/hosts/spike/dashboards.nix`, so a switch replaces any edited or added in the UI.
  The Claude dashboard splits sessions, tokens and cost by account, naming each Claude Code series' `user_email` `personal` when it is `personalEmail` in that file and `work` otherwise, with `label_replace`.
  Prometheus keeps a year of samples.
  The Backlogic dashboard and the Claude one read backlogic's tickets from `backlogic-aaron` through the `yesoreyeram-infinity-datasource` plugin, counting open and claimed tickets from `/api/snapshot` and charting each done ticket's spend and resolution from `/api/done`.
  Its time range picks the done tickets, through Grafana's `${__from}` and `${__to}` in each query's `/api/done?from=&to=` URL, which Grafana's frontend expands.
  Each selector wraps its tickets in `$append([], …)`, because the plugin fails a query whose selector matches nothing.
  It opens on the last 7 days, and a wider range reaches older done tickets too, because `/api/done` keeps the ones backlogic archives 7 days after `doneAt`, which `/api/snapshot` leaves out.
  The plugin's token is a backlogic API token, minted by the owner in backlogic's settings, in `/var/lib/grafana/backlogic-token`, owner `grafana`, mode 600, written by hand.
  Grafana starts with an empty one there when none was written, because a missing file fails its provisioning and stops it, and the backlogic panels show errors until the token is filled in.
  Grafana's plugins are declared, so the drilldown apps it otherwise installs itself are declared beside it.
  Its alerts are provisioned from `modules/hosts/spike/monitoring.nix` and post to a Discord channel through a webhook whose URL lives in `/var/lib/grafana/discord-webhook`, owner `grafana`, mode 600, written by hand, read by Grafana only when it starts.
  Grafana refuses to start with an empty URL there, so it writes a placeholder pointing nowhere when none was written, and alerts go nowhere until the webhook is filled in.
  They fire, for spike and framer each, when a host booted in the last 30 minutes, the kernel OOM-killed a process in the last 10 minutes, available memory stays under 1.5 GiB or swap over 80% used for 5 minutes, or `/` has over 80% of its inodes or 85% of its space used.
  They also fire when a systemd service on spike restarts more than 3 times in an hour, from node_exporter's restart metrics, which framer's node_exporter leaves off, and when a systemd unit stays failed for 5 minutes.
  They fire when an exporter Prometheus scrapes has not answered for 10 minutes.
  Grafana runs on spike, so a hung spike raises nothing until it comes back, when the reboot alert fires.
  Prometheus takes Claude Code metrics over OTLP on `localhost`, from `aaron`'s sessions, backlogic's runner's among them, through its `settings.json` on spike alone, each labelled `job` by `OTEL_SERVICE_NAME`.
  That `settings.json` also carries, on spike alone, an `autoMode` block telling the auto mode classifier that its production is a home server, so routine reads, restarts and post-land pulls there stop being denied.
  Every other host's starts sessions in `bypassPermissions` mode with its warning skipped, and carries an `autoMode` rule for when a session is switched back to auto mode, letting a session pipe the clipboard into a secret file on spike over SSH without reading it, which is how the backlogic token above gets there from the browser.
  `claude-limits.timer` writes each account's session and weekly limits every 10 minutes for node_exporter's textfile collector, one `claude-limits-<account>.prom` per account labelled `account`, read as `backlogic-runner` from `/api/oauth/usage`, the undocumented endpoint behind `/usage`, with the token in the runner's `.credentials.json` for that account.
  The endpoint rate limits each token, and a status line older than its 5 minute wait after a refused fetch retries every 30 seconds, which kept `aaron`'s `~/.claude` token refused, so it reads the runner's tokens, which the runner's own sessions keep fresh.
  It polls no more often because the endpoint answered 87% of its 2 minute polls with HTTP 429, and an account it refuses keeps its last reading, whose age the Claude dashboard shows, while the unit still succeeds so the failed-unit alert stays quiet.
- Backlogic's `backlogic-aaron` runs backlogic's own `compose.yaml` in Docker, built on spike from the detached checkout `/srv/backlogic`, cloned by hand as `aaron` over SSH (`modules/hosts/spike/backlogic.nix`).
  The `backlogic-compose` command runs `docker compose` there with spike's settings and an override that runs the container as `aaron`, uid `1000`, on the host's network, on `:4200`, with `~/backlogic-data/aaron` bind-mounted as its store.
  As `aaron`, the owner's admin verbs keep sharing that store with the container, and the peer token there stays readable to it.
  On the host's network, `:4200` stays behind spike's firewall instead of Docker's own rules, and the peer `ideas.noodlebra.in` resolves through spike's `/etc/hosts`.
  The `backlogic` command on the path runs `/srv/backlogic/bin/backlogic`, so the admin verbs, which open the store itself, run the code the instance runs.
  The instance's updates folder, `~/backlogic-data/aaron/updates`, is its Windows Update's setting and backlogic-switch's protocol with it (backlogic's `docs/decisions/update-notice.md`), started once with `automatic` so spike installs every push until Aaron chooses *Let me choose* on the page.
  `backlogic-switch.timer` fetches backlogic's `main` in `/srv/backlogic` each minute as `aaron`, whose SSH key reads the private repository, touches the folder's `checked` after each fetch so the page can say when it last looked, and writes it with the changelog lines it adds to the folder's `available`.
  It installs at once the commit an owner chose there in `install`, refusing one not on `main` or one the instance already passed.
  While `automatic` is there, once `main` has moved and then stayed put for 30 minutes, recorded in `/var/lib/backlogic-switch/pending`, checks it out and runs `backlogic-compose build`, then `up --detach --wait`, so a run of landings costs one build and one restart.
  A commit that does not descend from the running one is skipped, so older code never opens a store newer code migrated, which it refuses.
  A build that fails puts the checkout back and is recorded in the folder's `failed`, which the automatic install skips until `main` moves again; one that builds keeps its checkout even when it fails to start, since it may already have migrated the store.
  Once the instance is up, it runs `claude plugin marketplace update backlogic` and `claude plugin update backlogic@backlogic` in each of `aaron`'s Claude configs, `~/.claude` and `~/.claude-work`, since a third-party marketplace's `autoUpdate` takes an update only when a session starts.
  When that update changed the plugin's `rules/`, `.claude-plugin/` or `hooks/`, judged from its installed version before and after, it then runs `bin/rules-fresh-session` in each, one Haiku turn that fails the unit, naming each rule, unless a fresh session received the whole base (backlogic's `docs/decisions/rule-layers.md`).
  It skips that check, saying why, when the plugin's commit is not the one checked out, since the marketplace serves `main` and the check compares against the checkout's rules, so an older commit an owner chose would fail it.
  It redeploys production unattended and never touches `~/workspace/jimbo`, so that checkout's `main` stays clean.
  Its runner, `backlogic-runner-aaron`, runs as the system user `backlogic-runner`, outside `wheel` and without `sudo`, so no session it launches can be root, from the detached checkout `~/workspace/backlogic--service` under its home `/var/lib/backlogic-runner`, beside its own clones of the projects its sessions work in, with its mise shims on its PATH so its sessions find `bin/check`'s tools, and a switch never restarts it, since its sessions run inside the unit.
  Its unit runs at `Nice` 10 and a CPU and IO weight of 20 against everything else's 100, and its sessions, their `/dev/shm` temp files included, share a `MemoryHigh` of 6G, a `MemoryMax` of 8G of spike's 15 GiB and a `MemorySwapMax` of 2G, since a cap that leaves swap free still spends RAM on zram, so Bowerbird and `backlogic-aaron` win under pressure.
  Its Claude Code settings, personal `CLAUDE.md`, skills and git config are links to `aaron`'s home-manager files, so its sessions behave as his did, while its Claude logins, its token in `~/runner.token` and its GitHub tokens are its own, made by hand.
  It has a Claude config directory per account, `~/.claude` and `~/.claude-work` under its home, each logged in by hand, which `runner.json`'s `accounts` name by `configDir`.
  Its clones are over HTTPS, and `~/.gitconfig` swaps `aaron`'s `gh` credential helper for one handing git the fine-grained token in `~/.config/github-tokens/<owner>`, mode 600, one for `kranners` and one for the `backlogic` organisation, since a fine-grained token reaches one owner's repositories alone.
  The instance writes `runner.json` to `/var/lib/backlogic-runner-config`, owner `aaron`, group `backlogic-runner`, setgid, so the runner and its sessions' hooks read what the instance writes.
  That directory is bind-mounted into the container at the same path, and named by `--config` in the override's entrypoint, the image's own with that flag added, since `compose.yaml` passes no `--config`.
  It lands through its own queue, `~/land-queue`, since `land-on-main`'s default under `/tmp` belongs to whichever user landed first.
  Caddy serves `backlogic-aaron` at `https://backlogic.spike.cute.engineer` (`modules/hosts/spike/backlogic.nix`), whose DNS-only A record points at `10.100.0.1`, so it is reached over WireGuard alone.
- Home Assistant (`modules/hosts/spike/home-assistant.nix`) runs as the NixOS `home-assistant` module, serving `:8123` open on `wlp2s0` and `wg0` alone.
  Its secrets, `latitude`, `longitude`, `elevation` and `panel_user_id`, live in `/var/lib/hass/secrets.yaml`, owner `hass`, mode 600, written by hand.
  Trusted-network auth skips the login screen for framer's DHCP-reserved LAN address, `192.168.4.25`, logging it in as the user `panel_user_id` names, so the panel at `http://spike.local:8123/nixos-lovelace/panel` never shows one while every other client still logs in.
  `panel-wallpapers.timer` fetches a random page each of wallhaven's `nature` and `aerial view` wallpapers daily, excluding any tagged with people, into the media folder `/var/lib/hass/media/wallpapers`, keeping the newest 60, portrait ones because framer stands on its side, and WallPanel's screensaver shows them, cropped to fill the screen.
  That panel is a Lovelace dashboard the module provisions, a WallPanel screensaver of the time and Open-Meteo's forecast for `weather.home`, zoomed to twice their size across the panel's full width so they read from across the room.
  WallPanel never clears a style a profile set, so the day profile sets the info box's opacity back to `1` after the night profile's `0.3`, and its error alerts are off, because the daily fetch prunes wallpapers its hourly media list still names.
  From the moment framer's satellite, `assist_satellite.framer`, starts listening, while it thinks and answers, and for 30 seconds after so the reply can be read, the trigger-based `binary_sensor.framer_conversation` is on, unless the conversation was dismissed, which turns it off until the next wake starts listening, and it starts off whenever Home Assistant starts, and the panel dims the whole screen under a gradient darkest at the bottom, pulsing while it listens, with what was heard and the reply in large white text over it.
  An automation turns off `input_boolean.panel_screensaver`, WallPanel's `screensaver_entity`, as that sensor turns on, and WallPanel's `profile_entity`, `sensor.panel_profile`, reads `voice` while it stays on, a profile with no idle timeout, so the screensaver stays out of the way for the whole conversation, and otherwise reads `input_text.wallpanel_profile`'s day or night.
  wyoming-satellite listens for the wake word again as soon as it has a transcript, so a wake while Home Assistant is still answering aborts that answer, and the aborted run's error can reach the satellite after the new run starts, leaving Home Assistant listening for audio that never comes; an automation reloads the satellite's config entry once it has been listening for 30 seconds, twice the 15 seconds after which Home Assistant's own speech detection gives up.
  The text comes from the trigger-based template sensor `sensor.framer_voice`, whose `heard` and `reply` attributes framer's satellite sets through the local-only webhook `framer-voice`, because Home Assistant keeps no entity with a satellite's transcript.
  Under the clock and weather, past the screensaver, a tile toggles `switch.framer_mute`, the mute switch Home Assistant's Wyoming integration gives every satellite, which pauses framer's satellite, wake word and all, until it is turned off again.
  While it is on the assistant is off: `sensor.panel_profile` reads `off` ahead of every other profile, a WallPanel profile showing only the time and temperature, centred in large grey text on black, through a card styling itself rather than WallPanel styles, which a profile never clears, and an automation starts the screensaver as it turns on.
  The local-only webhook `framer-assistant-toggle` toggles it, for framer's power button.
  The local-only webhook `framer-dismiss`, for framer's volume buttons, fires `framer_dismissed`, which turns the conversation sensor off, and reloads the satellite's config entry while it is listening, thinking or answering, because dropping its connection is the only way to cancel the pipeline it is running.
  The dashboard's second view, `framer` at `/nixos-lovelace/framer`, the only one WallPanel leaves alone (`enabled_on_views`), is the panel's remote control: `light.framer_screen` for its screen and brightness, that mute tile, and `switch.framer_screen_and_microphone_off`, which turns both off at once and back on together.
  `light.framer_screen` runs framer's `panel` command through `rest_command.framer_panel` against framer's `panel-remote` on `10.100.0.5:8124`, and reads its brightness from `sensor.framer_screen_brightness`, polled there every 30 seconds and after each change, so the screen's schedule steps show within 30 seconds.
  Turning it on is `panel on`, the schedule's brightest level, and like every `panel` override it lasts until the schedule's next step.
  Every switch writes a hash of that dashboard, Home Assistant's version and its Lovelace modules to `/var/lib/hass/www/panel-version`, served without a login at `/local/panel-version`, for the kiosk to watch.
  Open-Meteo, Remote Calendar and Wyoming are set up by hand through their config flows and persist under `/var/lib/hass`.
  Google Calendar is set up the same way, from an OAuth client of type Web application in Google Cloud with the Calendar API enabled and `https://my.home-assistant.io/redirect/oauth` as its redirect URI, entered under Application Credentials, with read-write access chosen in its options.
  Google Tasks stands in for Apple Reminders, which has no API off a Mac, one `todo.*` entity per task list, polled every 30 minutes, also set up by hand through its config flow with OAuth web-application credentials from a Google Cloud project with the Google Tasks API enabled and the consent screen published, since unpublished credentials expire every 7 days.
  Assist adds, checks off and removes items in those lists by its built-in `HassList*` intents once the entities are exposed to it, with no LLM, but has no intent to read a list out, and since OpenClaw left framer nothing reads one aloud, butler's voice lane included.
  Assist answers today's and tomorrow's forecast locally through the module's own `WeatherForecastToday` and `WeatherForecastTomorrow` sentences, which read Open-Meteo's daily forecast for `weather.home`, because the built-in weather intent only reports the current conditions.
  That built-in intent answers "what's the weather" only once `weather.home` is exposed to Assist, a hand step in Home Assistant's settings.
- Voice (`modules/hosts/spike/voice.nix`) runs `wyoming-faster-whisper-en` on `127.0.0.1:10300` and `wyoming-piper-en` on `127.0.0.1:10200` for Home Assistant's Assist pipeline, loopback only because Home Assistant runs on the same box.
  The recogniser is NVIDIA's English Parakeet through sherpa-onnx, the server's own default for English, which on spike transcribes a short command in under half a second, about three times faster than whisper's `base-int8`, which misheard commands.
  Both are niced to `10` so a transcription never competes with Bowerbird, and both download their model, Parakeet from sherpa-onnx's GitHub releases and the voice from Hugging Face, into the unit's state directory on first start, so that start needs the internet and a minute.
- Caddy (`modules/hosts/spike/caddy.nix`) serves HTTPS on `443`, open only on `wg0`.
  Its certificates come from Let's Encrypt by DNS-01, through the `caddy-dns/cloudflare` plugin built in with `pkgs.caddy.withPlugins`.
  It reads the cloudflare-dyndns token as the systemd credential `cloudflare-token`, through Caddy's `{file.*}` placeholder, so the token never reaches the Nix store.
  Spike's network answers every DNS query itself, whatever server it is sent to, and hides answers with private addresses, so Caddy skips its own propagation check, `propagation_timeout -1`, and waits 30 seconds for Let's Encrypt instead.
  The same filter hides `app.bowerbird.cute.engineer` and `vnc.framer.cute.engineer` from anything resolving through the home network.
- Bowerbird (`modules/hosts/spike/bowerbird.nix`) runs the job application pipeline from a clone of `kranners/bowerbird` at `/srv/bowerbird`, made by hand as `aaron` with `npm ci` run in it.
  Its secrets and settings live in `/srv/bowerbird/.env`, owner `bowerbird`, mode 600, written by hand.
  `bowerbird-compose.service` runs `compose.production.yml` as root: Postgres on `127.0.0.1:5432` and the portal on `:3000`.
  It never builds the portal's image, which `bin/deploy` builds before restarting it, because rebuilding on every restart retried a broken build every two minutes.
  `bowerbird-display.service` runs Xvfb `:99` with openbox for the house cycle alone, unwatched since nothing needs to see it, and `bowerbird-worker.service` runs `jobs/src/worker.ts` on it, both as the system user `bowerbird` with state in `/var/lib/bowerbird`.
  Each signed-in member gets their own `bowerbird-display@<display number>.service`, running Xvfb, openbox and x11vnc together on their own display number and VNC port, `5900` plus their number past the house's own `99`; one shared `bowerbird-vnc-proxy.service` (websockify, `--token-plugin TokenFile`) on `:6080` picks a connection's target by the member's own `vncToken` in its `?token=`, read fresh from `/var/lib/bowerbird/vnc-tokens` on every connection.
  `bowerbird-sync-displays.timer` writes that file and starts or stops each member's display unit every minute, from `members.displayNumber`/`vncToken` in Postgres, read directly since nothing on the portal side notifies it of a new member or a rotated token.
  The worker starts once the house display is up and Postgres accepts connections, and every unit that needs the checkout is skipped while it is missing.
  A stop signals the worker alone, `KillMode=mixed`, which finishes the runs it has going before it exits, and systemd waits 35 minutes, `TimeoutStopSec`, before `SIGKILL`, five more than the worker's own cap on that wait.
  `bowerbird-backup.timer` dumps the database nightly into `/var/lib/bowerbird-backups`, keeping 14 days.
  Caddy serves the portal at `https://app.bowerbird.cute.engineer` and noVNC under its `/vnc/`, where `REMOTE_VIEW_URL` points, and noVNC finds `/vnc/websockify` relative to its page.
  The name's DNS-only A record points at `10.100.0.1`, so the portal is reached over WireGuard alone, and ports `3000` and `6080` are closed to everything but localhost.
  `nodejs_24`, the Node the worker unit runs, is also on the system path so `npm ci` works for `aaron`.
  To deploy by hand: `ssh aaron@spike.local /srv/bowerbird/bin/deploy`, the repository's script, which pulls `main`, runs `npm ci` and restarts only the units whose code changed.
  GitHub Actions runs the same script on every push to Bowerbird's `main`: it joins `wg0` as the peer `github-actions` and logs in as `aaron@10.100.0.1` with a key whose forced command is `/srv/bowerbird/bin/deploy`.
  The script refuses to deploy while a branch other than `main` is checked out in `/srv/bowerbird`, so checking one out there pauses deploys while it is tested.
- Hardware watchdog (`wdat_wdt`) is armed by systemd, and the kernel reboots 10 s after a panic.
- Its only swap is `zramSwap` at the module's defaults, half of RAM compressed with zstd, so cold pages compress in memory and pressure builds gradually instead of running straight into the OOM killer.
  `vm.oom_dump_tasks` is off, so the OOM killer acts at once instead of first logging every task, and Nix collects garbage during a build once `/` has under 20 GiB free, until 60 GiB is.
- Nix collects garbage daily, where every other host does weekly, because each backlogic `bin/check` the runner runs leaves a dead build of thousands of files in the store, and a week of them filled the root filesystem's inode table while it still had blocks free.
  Even daily, the store grew about 48 GiB in a day, which is why the build-time collection starts at 20 GiB, and `auto-optimise-store` hard-links identical files as they arrive.
- `/tmp` sits on the root filesystem and ages out entries untouched for a day, overriding systemd's own `tmp.conf` rule in `modules/hosts/spike/tmp.nix`, which judges directories by birth and modification time alone, because every directory there is read daily, which kept their access time fresh and the age from ever passing.
  The runner's checks leave thousands of entries there a day.
  The same file ages out Deno's `gen` cache, in `aaron`'s and the runner's homes, after 2 days unused, since every new lane path adds a fresh set of entries to it.
- The journal keeps at most 1 GiB.
- Spike is framer's remote builder (`modules/hosts/spike/remote-builder.nix`): framer's root logs in as the system user `nix-builder`, whose key may only run `nix-daemon --stdio`, and which Nix trusts.
  Spike's nix-daemon runs at idle CPU and IO priority, so those builds, and every other, yield to Bowerbird.
- WireGuard `wg0` on UDP `51820` at `spike.cute.engineer` (kept current by cloudflare-dyndns, token in `/var/lib/secrets/cloudflare-dyndns-token`), spike is `10.100.0.1`.
  Its private key is generated on first boot at `/var/lib/wireguard/private`.
  Its peers are `piggys-MBP` at `10.100.0.2`, `phone` at `10.100.0.4`, `phone-2` at `10.100.0.9`, `framer` at `10.100.0.5`, `rylee` at `10.100.0.6`, `rylee-2` at `10.100.0.10`, `pilot` at `10.100.0.11`, `tower` at `10.100.0.7`, `windows` at `10.100.0.8`, and `github-actions` at `10.100.0.3`, whose private key lives only in Bowerbird's GitHub secrets.
  spike forwards from Aaron's own peers, `piggys-MBP`, `phone`, `phone-2` and `framer`, to any other peer, and its `spike-wg0-forward` chain drops every other packet forwarded in from `wg0` but replies, so Rylee's `rylee`, `rylee-2` and `tower`, `github-actions` and `pilot` reach spike alone.
  Spike resolves `ideas.noodlebra.in`, Rylee's backlogic instance, to `rylee-2` at `10.100.0.10`.
  It declares `ip_forward` itself, which it otherwise had only because Docker set it.
  There is no NAT for `10.100.0.0/24`, so a peer reaches nothing on the LAN through spike.
  Caddy's `vnc.framer.cute.engineer` is spike's own `443`, open to every peer, so it still reaches framer's noVNC from `rylee` and `github-actions`.
- Claude Code runs on two accounts here, `aaron@cute.engineer` logged in under `~/.claude` and the work account under `~/.claude-work`, the `CLAUDE_CONFIG_DIR` of anything that uses it.
  Home-manager writes the same `CLAUDE.md`, skills and `settings.json` into both, on spike alone, but neither login, `.credentials.json` or `.claude.json`, and a directory's first logged-in session installs the plugins its `settings.json` enables, which `claude plugin install` cannot, since it writes to that read-only `settings.json`.
  Backlogic's runner, which logs in to both accounts under its own home, spends the personal account first and moves to the work account only while personal is at its limit, capped low enough that most of the work account's week stays free, through `runner.json`'s `accounts`.
  Remote Control runs on the work account, so it keeps working once the runner has spent the personal week, while butler runs on the personal one until it moves to another account at the limit.
- Claude Code Remote Control (`claude-remote-control.service`) serves sessions from `~/workspace` to claude.ai/code as `spike`, on the work account, capped at a `MemoryHigh` of 6G, a `MemoryMax` of 8G and 2G of swap, with `OOMPolicy=continue` so an OOM kill ends one session rather than every one.
- Butler (`butler.service`, `modules/hosts/spike/butler.nix`) is Aaron's personal assistant bot, an instance of `kranners/claude-discord-threads` with its own Discord bot application and private guild, on the personal `aaron@cute.engineer` account while it has usage left and on Aaron's other accounts after it.
  It runs as the system user `butler`, outside `wheel` and without `sudo`, from its own checkout `/var/lib/butler/claude-discord-threads`, with sessions starting in `/var/lib/butler`, at most 2 at once, capped at a `MemoryHigh` of 2G, a `MemoryMax` of 3G and 1G of swap, with `OOMPolicy=continue`.
  `ProtectHome`, `ProtectSystem=strict`, an empty `/var/lib` with only its home bound back in, a hidden `/srv` and `ProtectProc=invisible` keep it out of `/home`, other services' state and other processes, and let it write only under its own home.
  Its `~/.claude/settings.json` and persona `~/.claude/CLAUDE.md` are links to files the module writes.
  The settings allow only `Read`, `Glob`, `Grep`, `WebSearch`, `WebFetch` and editing its memory's `core`, `skills` and `journal`, deny every tool that runs or schedules, editing `~/.claude` and its memory's `.git`, and reading `/proc`, `/run`, `~/.ssh`, `~/.cache`, its iCloud session, Outlook token and rclone config and its own Discord state, and `DISCORD_PERMISSION_MODE=dontAsk` refuses anything not allowed instead of asking.
  Its other tools are the module's `butler.commands`, each a wrapper the daemon runs itself as the MCP tool `mcp__commands__<name>`, listed in the JSON manifest `DISCORD_COMMANDS_FILE`, since `Bash` stays denied.
  Each command's rules match its leading arguments and say which lanes may run it, a conversation, a scheduled run or a voice request.
  Only `mail-send` and `messenger-send` both taint the thread and send data out, so they alone wait for Aaron's approval through a Discord button, and everything else, the web and the browser included, runs without asking, because Aaron wants approval only for writes to real people and payments.
  The daemon's gate always counts `WebFetch` and `WebSearch` as egress, so in a thread that has sent something the web asks too until `/clear`, and any other rule setting `taints` would bring those prompts back everywhere.
  Each command's `credentials` join the unit's `LoadCredential`, which systemd reads from root-owned files in `/var/lib/secrets` before dropping to `butler`, so a wrapper reads them from `/run/credentials/butler.service`, and the unit fails to start while any of those files is missing.
  Each command's `skill` is linked into `~/.claude/skills`.
  Its bot token is `DISCORD_BOT_TOKEN` in `/var/lib/secrets/butler.env`, owner `root`, mode 600, written by hand and read by systemd before it drops to `butler`.
  It may spend any of Aaron's Claude accounts, each a one-year token from `claude setup-token`, one `<number> <token>` line per account in `/var/lib/butler/.claude-accounts/tokens`, owner `butler`, mode 600, written by hand with a script that pipes the token over SSH, and denied to its own `Read`.
  Every turn spawns `butler-claude`, its `CLAUDE_CODE_EXECUTABLE`, which runs `claude` at once with the first account in number order not cooling down, and meanwhile sends that account a one-token Haiku request in the background, so no turn waits on it.
  A 429 there writes the account's `anthropic-ratelimit-unified-reset` to `/var/lib/butler/.claude-accounts/cooldown/<number>`, and a 401 or 403 an hour from now, so later spawns skip it until then, and a turn the limit cut short resumes on the next account when the daemon retries it.
  When every account is cooling down it runs the first anyway, so the daemon's retry keeps trying.
  Each choice is logged by account number to the journal under `butler-claude`.
  Its allowlist is `/var/lib/butler/.claude/channels/discord/access.json`, re-read on every message, written by hand: `{"dmPolicy":"allowlist","allowFrom":["193903125994799114"],"groups":{"<channel id>":{"requireMention":false,"allowFrom":[]}}}`.
  The unit skips starting until `/var/lib/secrets/butler.env` and the checkout exist, so after writing them by hand run `systemctl start butler`.
  The checkout is cloned once by hand as `butler` from `git@github.com:kranners/claude-discord-threads.git` with the deploy key `/var/lib/butler/.ssh/claude-discord-threads-deploy`, owned by `butler`, mode 600.
  `butler-pull.timer` pulls its `main` every 2 minutes as `butler`, over SSH with that read-only deploy key through `GIT_SSH_COMMAND`, and when `HEAD` moved its root `ExecStartPost` restarts `butler`, so it needs no `sudo`.
  `modules/hosts/spike/butler-tools.nix` gives it framer's `github-issue` and `backlogic-ticket` wrappers and a `calendar` one, and `modules/hosts/spike/butler-mail.nix` framer's `mail` and a `mail-send`, each with a skill from `modules/hosts/spike/butler-skills` worded for Discord.
  They stay off until `butler.credentialedTools = true`, set once their credentials, copied from framer, are in `/var/lib/secrets`, because a missing `LoadCredential` source stops the unit starting.
  `mail` and `mail-send` exist once `butler.mail.accounts` has an account, which `butler.credentialedTools` gives Fastmail and Gmail, each logging in with an app password from `/var/lib/secrets/butler-email-<account>-password`.
  `mail` reads and archives every account through one himalaya config, and `mail-send <account> <to> <subject>` sends a plain-text body from stdin to one address, with a subject of at most 200 bytes and no control characters but newlines and tabs in the body, through the account's SMTP, saving a copy to Fastmail's `Sent` since Fastmail keeps none of SMTP's.
  `mail-send`'s rule both taints and sends out, so the gate taints the thread before checking it and every send waits for Aaron's button, showing the whole body, because `mail-send` refuses a send whose args and body take more than 1400 characters as the approval's JSON, which the daemon cuts off at 1500, and a scheduled run is refused it.
  `modules/hosts/spike/butler-outlook.nix` adds Outlook, a personal Microsoft account, as the account `outlook`, behind `butler.outlook.enable` with its `address` and `clientId`, the ID of Aaron's own Entra app for personal accounts with public client flows allowed.
  It reads and sends over IMAP and SMTP with XOAUTH2 rather than himalaya's Microsoft Graph backend, because Graph's search refuses the flag filters `mail` lists unread mail with.
  Its tokens come from ortie's device grant against the `consumers` tenant, scoped to IMAP, SMTP and `offline_access`, stored by `sudo -u butler butler-outlook-login` in `/var/lib/butler/.local/share/ortie/outlook.json`, which ortie refreshes there itself when himalaya asks it for a token.
  `modules/hosts/spike/butler-drive.nix` gives it `drive`, behind `butler.drive.enable`, which lists a folder of My Drive, searches the names and text of every file Aaron can see, and prints a file as text, Docs and Slides exported as text, Sheets as CSV and PDFs through `pdftotext`, cut off after 40,000 bytes.
  It runs rclone with the `drive.readonly` scope and Aaron's own Google OAuth desktop client, from `/var/lib/butler/.config/rclone/rclone.conf`, written by `butler-drive-login` run as `butler` over an SSH session forwarding port 53682 for rclone's browser sign-in, in a Google Cloud project of its own, apart from Home Assistant's, with the consent screen published so the token outlives 7 days.
  A search result names its folder by ID, which `drive cat` reads through rclone's `root_folder_id` connection string, or `shared_with_me` for a shared file with no folder of Aaron's.
  `calendar` lists, reads and adds Google Calendar events through Home Assistant on `127.0.0.1:8123`, with a long-lived token of its own, "Butler on spike", from `/var/lib/secrets/butler-home-assistant-token`, and takes only a `calendar.*` entity and ISO dates, never a raw API path.
  `github-issue` reads a fine-grained GitHub token from `/var/lib/secrets/butler-github-issues-token`.
  `backlogic-ticket` files to `backlogic-aaron` on `127.0.0.1:4200` with framer's owner token, copied into `/var/lib/secrets/butler-backlogic-token`.
  `modules/hosts/spike/butler-reminders.nix` gives it `reminders`, which reads, adds and completes Apple Reminders through pyicloud's CloudKit Reminders service, so an assertion requires pyicloud 2026.10.1 or later.
  Its iCloud session lives in `/var/lib/butler/.local/share/pyicloud`, beside an `apple-id` file naming the account, both written by `sudo -u butler butler-icloud-login <apple-id>`, which asks for the password and 2FA code and keeps only the trusted session.
  That session lasts about two months, after which `reminders` exits 75 asking for the login to be run again.
  Both set `PYTHON_KEYRING_BACKEND` to keyring's null backend, so no password is looked up in or written to a keyring.
  It answers with pictures through the daemon's `attach_file` tool, which `DISCORD_ATTACH_PATHS` limits to `/var/lib/butler/outbox` and the mood pictures, since the tool reads files outside Claude Code's own `Read` rules.
  `modules/hosts/spike/butler-render.nix` gives it `render`, which screenshots HTML, SVG, Mermaid or Vega-Lite from stdin into a PNG in the outbox with Playwright's Chromium, its libraries inlined from pinned bundles and the page cut off from the network by offline mode, routes that abort every request and a dead proxy and resolver, because it runs in threads that read private data without approval.
  `modules/hosts/spike/butler-self-fix.nix` gives it `self-fix`, so Aaron can ask it to fix itself: `self-fix start` writes the request from stdin to `/var/lib/butler/self-fix/queue/<id>.json`, and `self-fix status <id>` prints the session's link from `/var/lib/butler/self-fix/sessions/<id>`.
  `butler-self-fix.path` runs `butler-self-fix.service` as root whenever the queue is not empty, which runs `claude --cloud` as `aaron` from `~/workspace/jimbo` under `script`, since it refuses without a terminal, with a preamble telling the session to `add_repo` the other repositories and land the fix on `main`.
  It uses `~/.claude`, the personal account, unless butler's `cooldown/1` is in the future, then `~/.claude-work`, and marks `~/workspace/jimbo` trusted in that account's `.claude.json` first.
  The module's `jimbo-switch.timer` then deploys a jimbo fix: every 5 minutes, as `aaron` in `~/workspace/jimbo`, it fast-forwards to `origin/main` and runs `nh os switch .`, only while the checkout is on `main` and clean, never restarted by the switch it runs, and it records a commit whose switch failed in `/var/lib/jimbo-switch/failed` so it waits for the next one.
  `modules/hosts/spike/butler-photos.nix` gives it `photos`, which lists and saves Aaron's iCloud Photos as JPEGs in the outbox through the reminders' pyicloud session.
  `modules/hosts/spike/butler-imagine.nix` gives it `imagine`, which generates pictures, of Butler himself from his avatar when asked, with OpenAI's image API and the restricted key `/var/lib/secrets/butler-openai-api-key`, behind `butler.imagine.enable`.
  Each picture command deletes outbox files older than two days when it writes one.
  `assets/butler/moods` holds pictures of Butler feeling each mood, named by mood, and its persona attaches the one that matches how it feels to any reply without another picture.
  `modules/hosts/spike/butler-messenger.nix` gives it `messenger-chats`, `messenger-read` and `messenger-send`, curl and jq against the Matrix client API of spike's own homeserver, as `@aaron:spike` with the access token in `/var/lib/secrets/butler-matrix-token`, and the skill `messenger`.
  They stay off until `butler.messenger.enable = true`, set once `messenger-setup` has written that token and logged the bridge in to Facebook.
  `messenger-chats [--marketplace]` lists the 50 most recently active bridged chats, a Marketplace one being a child of a bridged space, since mautrix-meta bridges only Marketplace's folder as a space and leaves its personal space unbridged, and `messenger-read <room> [count]` prints a bridged chat's latest messages.
  `messenger-send <room>` sends its stdin as one message, at most 1000 characters and 1400 as the approval's JSON preview counts them, escapes and UTF-16 included, with no control characters but newline and tab, so the approval's 1500-character preview shows all of it, only from a conversation, only into a bridged chat, never starting with `!`, which the bridge reads as a command, and at most 10 an hour, counted in `/var/lib/butler/.local/state/messenger-sent`, because Meta flags an account that sends a lot.
  Its rule both taints and sends data out, so the gate taints the thread first and then asks Aaron, and every send needs his approval, even in a thread that read nothing private.
  `modules/hosts/spike/butler-health.nix` gives it `garmin` and `hevy`, each off until its own `butler.garmin.enable` or `butler.hevy.enable`.
  `garmin` reads sleep, HRV, Body Battery, stress, steps, activities and profile settings from Garmin Connect's official Personal API, through one fixed POST that trades its key for a JWT and fixed GET paths on `personal.connectapi.garmin.com`.
  Its key, made in Garmin Connect's web settings for at most a year, is `/var/lib/secrets/butler-garmin-api-key`, which it trades for a JWT kept in `/var/lib/butler/.cache/garmin/token` until an hour before its `exp`.
  Its output passes through `butler-health/garmin-clean.jq`, which keeps numbers, dates and enum-like codes and drops every free-text field and every coordinate, GPS track and polyline.
  `hevy` reads workouts, exercise history, templates and routines through the Hevy web app's private API on `api.hevyapp.com`, with the web client's key `shelobs_hevy_web`, so it needs no Hevy Pro and can break without notice.
  Hevy's web login needs a reCAPTCHA, so the session is not made from a password: `sudo -u butler hevy login` takes the `auth2.0-token` cookie from a logged-in browser and keeps its rotating access and refresh tokens in `/var/lib/butler/.cache/hevy/session.json`, refreshed under a lock.
  It changes only the routines `Butler A` and `Butler B` in the folder `Butler plan`, which `hevy bootstrap` creates once, through a draft stored under its sha256 by `hevy routine draft` and written by `hevy routine apply <slot> <sha256>`, which takes on stdin the diff it would apply, refuses unless that is the diff it prints now, so the diff butler shows Aaron is the real change, and reads the routine back and fails when Hevy saved anything different.
  `apply` and `bootstrap` run only in a conversation, without a button.
  Its memory is the private `kranners/butler-memory`, which `butler-memory-pull.timer` clones or pulls into `/var/lib/butler/memory` every 5 minutes as `butler`, with the read-write deploy key `/var/lib/secrets/butler-memory-deploy-key`.
  Each pull relinks every `skills/<name>` there into `~/.claude/skills` and every `core/*.md` into `~/.claude/rules`, skipping a name already taken, so a session loads them.
  Butler keeps its own `core`, `skills` and `journal` there, editing them with Claude Code's own tools and told by its persona to do so constantly, while `history`, `scripts` and `cron` stay Aaron's.
  `memory-note` appends its stdin to that day's `journal/YYYY-MM-DD.md`, commits and pushes it, and `memory-save` runs the repository's `scripts/check.sh`, which refuses a skill setting `allowed-tools`, then commits and pushes every change under `core`, `skills` and `journal` with its stdin as the message, both under the same `~/memory.lock` as the pull.
  Every pull rebases with `--autostash`, so edits butler has not saved yet survive it.
  Each `cron/<name>.md` there, through `DISCORD_CRON_DIR`, is a prompt the daemon runs at its `at` time on its `days`, in a new thread of `DISCORD_CRON_CHANNEL`, butler's `#general`, re-read every 30 seconds.
  `modules/hosts/spike/butler-voice.nix` gives it a voice endpoint, off until `butler.voice.enable = true`, set once the daemon on `main` serves it, because today's daemon refuses a manifest naming the `voice` lane.
  It sets the daemon's `DISCORD_VOICE_*` so it serves an OpenAI-compatible `/v1/chat/completions` on `127.0.0.1:18789`, loopback only because Home Assistant runs on the same box, and Home Assistant's llama.cpp integration calls it as the conversation agent of framer's Assist pipeline for anything its own intents cannot answer.
  It answers with `haiku` on butler's own Claude login, in the spoken persona `modules/hosts/spike/butler-voice.md`, hands a longer task to a Discord thread, and speaks that task's result on `assist_satellite.framer` through Home Assistant on `DISCORD_HA_URL`, with the calendar's Home Assistant token once `butler.credentialedTools` is on.
  Its bearer token is `/var/lib/secrets/butler-voice-token`, owner `root`, mode 600, which `butler-voice-token.service` generates before butler starts whenever it is missing, and which is pasted by hand into the llama.cpp entry.
  The `voice` lane may only read the agenda, count unread mail and add reminders to the `Inbox` list, because anyone in the kitchen, the television included, can talk to it.
  Its rules come before each command's own, and repeat their lanes, because the first rule that matches decides.
  The llama.cpp entry is added by hand in Home Assistant's UI, beside any older one, since an entry cannot change its base URL: base URL `http://127.0.0.1:18789/v1`, that token as the API key, and the one model the endpoint lists, with "Control Home Assistant" off in its conversation's options, then chosen as the conversation agent of framer's Assist pipeline, with "Prefer handling commands locally" left on, and the older entry deleted only once the pipeline answers through the new one.
  Home Assistant stores whether the agent streams once, when the entry is added, so the endpoint must already answer a streamed request then.
  `modules/hosts/spike/butler-browser.nix`, on while `butler.browser.enable`, its default, gives it a browser of its own: `butler-browser.service` runs Chromium as the system user `butler-browser` on Xvfb `:50`, its profile in `/var/lib/butler-browser/profile`, throttled at a `MemoryHigh` of 1.2G, killed at a `MemoryMax` of 1.5G and held to two cores, with `OOMPolicy=continue` so a renderer the kernel kills leaves the rest running, x11vnc on `127.0.0.1:5950`, a second, `-viewonly` x11vnc on `127.0.0.1:5951` and DevTools on `127.0.0.1:9222`.
  The daemon's `DISCORD_MCP_CONFIG` names a JSON file the module writes, which adds nixpkgs' `playwright-mcp` as the MCP server `browser`, attached over `--cdp-endpoint` to that Chromium, so butler drives it as `mcp__browser__*` tools but never reads its profile, hidden by butler's empty `/var/lib`.
  It sets `PLAYWRIGHT_MCP_USER_DATA_DIR` to that profile, because nixpkgs' wrapper otherwise sets `PLAYWRIGHT_MCP_ISOLATED`, which opens a fresh context without the profile's logins.
  Every `mcp__browser__*` tool is listed as `safe`, neither tainting nor egress, since the daemon counts a tool of an extra server that no list names as both and would ask for it, so the browser never asks and its persona confirms in plain text before paying, sending or posting.
  It leaves out `browser_run_code_unsafe`, which runs code in the MCP server as `butler`, `browser_evaluate`, `browser_file_upload` and `browser_drop`, which read local files, and `browser_take_screenshot`, which writes them.
  DevTools and both VNC ports have no authentication, so the chain `butler-browser-loopback` in spike's `OUTPUT`, for IPv4 and IPv6, resets every connection to `:9222` from anyone but `butler`, to `:5950` and `:5951` from anyone but `butler-browser` and to `:6081` and `:6082` from anyone but `caddy`, keeping backlogic's runner off the logged-in browser.
  The chain matches the connecting uid, so root, and `aaron` through passwordless sudo, can still reach DevTools.
  `butler-browser-view.service` bridges the full VNC with websockify on `127.0.0.1:6081`, and `butler-browser-panel.service` the view-only one on `127.0.0.1:6082`.
  Caddy serves `https://browser.spike.cute.engineer` to Aaron's own peers alone, aborting every other connection: `piggys-MBP`, `phone` and `phone-2` get `:6081`, for the one-time logins the `browser` skill asks Aaron for, and `framer` gets only `:6082` and `/active`, so the kitchen panel can watch it but never drive it.
  It also aborts every request carrying an `Origin` other than the site itself, because websockify never checks it, so a page open on one of those peers cannot open a cross-origin WebSocket to the VNC.
  Its matchers sit in a `route` block, because Caddy otherwise orders `abort` after `handle`, and the allowlist would never fire.
  `butler-browser-activity.service` writes `1` to `/run/butler-browser/active` while anything holds a DevTools connection open and `0` otherwise, and Caddy serves it at `/active`; playwright-mcp's `--idle-timeout` drops its connection a minute after its last tool call.
- Messenger (`modules/hosts/spike/messenger.nix`) bridges Aaron's Facebook Messenger, Marketplace chats included, into Matrix on spike, so butler can read and send it through plain HTTP on loopback.
  `tuwunel.service` is the homeserver `spike`, on `127.0.0.1:6167` alone, with federation, registration and encryption off.
  `mautrix-meta-facebook.service` is the bridge, an appservice on `127.0.0.1:29321`, built with goolm, since Matrix-side encryption is off and nixpkgs marks libolm insecure, with backfill on and only `@aaron:spike` allowed to use it, as admin.
  Its Matrix-side encryption is off, so the wrappers send and read plain events, while Messenger's own end-to-end encryption is still handled by the bridge, and the decrypted messages sit in the bridge's and tuwunel's databases on spike's disk.
  The NixOS module registers the bridge only with Synapse, so tuwunel's root `ExecStartPre` copies the bridge's registration, and a second one for double puppeting, into `appservice_dir` under its own state directory, because its `PrivateUsers` defeats sharing them by group.
  `matrix-double-puppet.service` generates that second registration's tokens once into `/var/lib/matrix-double-puppet`, and its `as_token` reaches the bridge's `double_puppet.secrets` through the module's `environmentFile`, so the bridge joins `@aaron:spike` to every chat and maps what Aaron sends from his phone to him.
  The same `ExecStartPre` generates `registration-shared-secret` in tuwunel's state directory once, for Synapse-style shared-secret registration, the one way to create a user with registration off.
  `sudo messenger-setup` creates `@aaron:spike` with it, not as a server admin, which tuwunel's shared-secret registration does not grant on its own, keeps its random password in `/var/lib/secrets/butler-matrix-password` and its access token in `/var/lib/secrets/butler-matrix-token`, or logs in again with that password when the token is missing or the server answers it with 401, then opens a direct chat with the bridge bot `@facebookbot:spike` and relays what is typed, hidden, to it line by line, printing its replies.
  Logging in is `login messenger-lite-android` there, Facebook's email or phone, password and two-factor code, then the Messenger secure storage PIN to restore encrypted history, or `skip`, since messenger.com closed in April 2026 and the Android flow keeps encrypted chats pushing.
  The bridge redacts the password and PIN messages once read.
  If the password file is lost while the token still works, nothing needs doing, and if both are lost, `users reset-password aaron <password>` through tuwunel's `admin_execute` or `--execute` sets a new one to write into `/var/lib/secrets/butler-matrix-password` before running `messenger-setup` again, since registering `@aaron:spike` again fails with the user in use.
  Meta forbids puppeting an account and may ask for a captcha or password reset after unusual activity, and it breaks the protocol now and then, after which the bridge needs a nixpkgs bump within days.
- mise is installed system-wide, and `programs.nix-ld` loads the tools it downloads, which are built for other Linuxes, such as backlogic's Deno and Python (`modules/hosts/spike/mise.nix`).
  Remote Control has `~/.local/share/mise/shims` last on its `PATH`, and backlogic's runner its own user's, so a session finds a repository's mise tools, and its git hooks run, while the system's `python3` still wins outside one.
  `/etc/mise/config.toml` trusts every `mise.toml` under `aaron`'s and the runner's `~/workspace/backlogic`, their worktrees included, and takes prebuilt Python, since building it from source fails here.
  A shim resolves its version from the working directory's `mise.toml`, so the file also sets Deno to the newest installed everywhere else, for hooks and tests that run Deno outside a checkout.
  A repository's tools are installed once by hand with `mise install` in its checkout, after `mise trust` outside `~/workspace/backlogic`.

### framer

`framer` is a Microsoft Surface Book 2 laptop running NixOS, a kiosk host (`desktop = false; kiosk = true;`), an always-on wall panel with no desktop environment.
Its files under `modules/hosts/framer` are plain NixOS modules, imported through `nixosSystemModule`, the same shape as spike's.
`modules/kiosk` is the generic appliance role: `services.cage` logs `host.username` into tty1 running a script that starts `wayvnc` in the background and execs the `ungoogled-chromium` the browser module uses, full screen on `kiosk.url`, which framer's host module sets to `http://spike.local:8123/nixos-lovelace/panel`, Home Assistant's dashboard on spike, under `nixos-lovelace` because NixOS's home-assistant module serves `lovelaceConfig` as a YAML dashboard of that name and leaves `/lovelace` empty, reached over the LAN so its trusted-network login matches framer's LAN address.
The script first scales `kiosk.output` by `kiosk.scale` and rotates it by `kiosk.transform` with `wlr-randr`, `eDP-1` by 2 and 90 degrees into portrait on framer, so Chromium takes its HiDPI scale and orientation from cage, because its own `--force-device-scale-factor` under cage drew into the top-left quarter of the screen.
Its cage unit restarts always, so a Chromium crash brings the dashboard back, and restarts on a switch that changes it, because nixpkgs otherwise leaves it stopped.
`getty@tty1` is masked, because cage conflicts with it and every switch started it, stopping the kiosk.
The script waits until `kiosk.versionUrl` answers before it starts Chromium, because Chromium never retries a page that failed to load, and `network-online.target` was reached seconds before framer's Marvell wifi connected, with `nm-online -t 60` as much as with NixOS's `nm-online -s`, and never waits for spike, which a power cut restarts too.
noVNC bridges wayvnc through websockify on `6080`; it and wayvnc's own `5900` are open on `kiosk.lanInterface`, which framer sets to `wlp1s0`, and `wg0` alone, with no VNC password, so the panel is a browser tab on the MacBook.
Caddy on spike serves that noVNC bridge at `https://vnc.framer.cute.engineer` (`modules/hosts/spike/framer-vnc.nix`), proxying to framer's `10.100.0.5:6080`, whose DNS-only A record points at `10.100.0.1`, so it is reached over WireGuard alone, with no gate beyond that.
`kiosk.schedule` drives `intel_backlight` through the `brightness` command: 60% from 07:30, 15% from 18:00, 0% from 23:30, back to 15% at 06:30.
Each step clears any override and applies whatever the schedule says for now, so a step `Persistent` replays late after a boot or switch still sets the right level.
Its `panel` command, `kiosk.panelCommand`, overrides the schedule until its next step, with `panel brightness <percent>`, `panel off`, `panel on` or `panel schedule`, through `/run/panel-brightness/override`.
Its `panel-wake` command jumps to the schedule's brightest level, then arms a 2 minute `systemd-run --user` timer back to the override, or else whatever the schedule says for now, replacing the one an earlier wake armed.
brightnessctl's udev rule gives the `video` group write access to the backlight, and `host.username` is in it, so `panel-wake` works for that user from any service, with no logind session or sudo.
`kiosk-reload-on-change.timer` fetches `kiosk.versionUrl` every minute and restarts `cage-tty1` when it differs from the last fetch, because WallPanel builds its screensaver once per page load and never picks up a changed dashboard on its own.
Sleep, suspend and hibernate are disabled, and logind ignores the lid switch and the power key, because the clipboard sits docked backwards on its base, and the power key toggles the assistant instead.

- SSH: `ssh aaron@framer.local` (key auth, resolved over mDNS), keys only, declared in `modules/hosts/framer`.
  Its avahi runs on IPv4 alone, because over IPv6 the churn of its privacy addresses made avahi mistake its own announcement for a conflict and rename framer `framer-2.local`, and a restart of `avahi-daemon` takes the name back if that happens anyway.
- Hardware: Intel i5-7300U, one 119 GB NVMe disk with a 1 GB ESP, wifi (`wlp1s0`) and no wired network, two batteries and an `intel_backlight` panel.
  `boot.loader.systemd-boot.configurationLimit` is 5, because that ESP only has room for a few generations.
  `thermald` and `upower` run for the laptop's thermals and battery.
  Bluetooth is off: linux-surface documents the Marvell wifi as unreliable while it is on.
  Its ALC298's jack detection is off, through the `snd-hda-intel` patch `framer-no-jack-detect.fw`, because its mic jack once read plugged in from boot with nothing in it, and capture moved to that silent jack.
  Its touchscreen needs linux-surface's patched kernel, which `modules/hosts/framer/surface.nix` takes from nixos-hardware's `microsoft-surface-common` module at its default `longterm` version, and `iptsd`, nixpkgs' `services.iptsd`, which turns the kernel's raw touch data into input events.
  `surface-control`'s `surface` command is on the path for the performance mode and the detachable base, run with `sudo` because its package ships no udev rules for a group to use.
  It carries the kernel's own fix for Rust 1.98's target spec, which 6.19 lacks, until nixos-hardware moves past 6.19 (NixOS/nixos-hardware#2079).
  No binary cache holds that kernel, so spike compiles it on every framer switch that changes it, at the idle priority its nix-daemon runs at.
- Hardware watchdog (`iTCO_wdt`) is armed by systemd, and the kernel reboots 10 s after a panic, the same as spike's.
- framer builds nothing itself, `max-jobs = 0`, and sends every build to spike over `ssh-ng` with root's key `/root/.ssh/id_ed25519`, generated by hand, because building OpenClaw, which framer once ran and no binary cache holds, ran the Surface out of memory, and its patched kernel is no lighter.
  Regenerating that key means updating `framerRootKey` in `modules/hosts/spike/remote-builder.nix` from `sudo cat /root/.ssh/id_ed25519.pub` on framer.
- The `brightness` command from `modules/brightness` drives framer's built-in panel, `intel_backlight`, with brightnessctl, which it picks over DDC/CI because `/sys/class/backlight` has a device here.
- WireGuard client `wg0` at `10.100.0.5`, one peer, spike, over UDP `51820` at `spike.cute.engineer`.
  The peer re-resolves that name every 5 minutes, `dynamicEndpointRefreshSeconds`, so a boot that failed to resolve it recovers and it follows spike's dyndns address, as `wireguard-wg0-peer-spike-refresh.service`.
  Its private key is generated on first boot at `/var/lib/wireguard/private`, the same as spike's.
  Spike's `framer` peer holds the public key of that private key, so regenerating it means updating the peer in `modules/hosts/spike/wireguard.nix` from `sudo wg show wg0 public-key` on framer.
- Voice (`modules/hosts/framer/voice.nix`) runs `wyoming-satellite` as `aaron`, named `framer`, on `:10700`, open on `wlp1s0` and `wg0` alone, for Home Assistant's Wyoming integration to find over zeroconf.
  It runs as `aaron` so `arecord` and `aplay` reach the PipeWire session cage's login starts, and it starts after `cage-tty1`.
  It restarts every 5 seconds with no start limit, because at boot it exits with `Network is unreachable` until the wifi connects, and systemd's default limit gave up on it after 4 seconds.
  `wyoming-openwakeword` listens on `127.0.0.1:10400` alone for the wake words `hey_mycroft` and `hey_butler` at a threshold of `0.7`, raised from the default `0.5` after it woke to overheard speech, and each detection runs `panel-wake`.
  `hey_butler` is a custom openWakeWord model, `modules/hosts/framer/wake-words/hey_butler.tflite`, trained on synthetic Piper speech, which is American, so it catches Australian and British voices less often than `hey_mycroft` does, and runs beside it until real recordings show it can replace it.
  The satellite records the 2 seconds before each wake and the command after it into `/var/lib/wyoming-satellite/recordings`, so that threshold can be tuned from real false wakes, and tmpfiles removes each after 14 days.
  It is patched to stop streaming, sending Home Assistant the end of the audio, when Home Assistant has heard no speech 6 seconds after a wake or 8 seconds after a follow-up question, because Home Assistant ends a command early only once it has heard speech start, so every false wake and unanswered question otherwise listened for its full 15 second timeout.
  It is patched to stop that command's recording when Home Assistant reports an error, because unpatched every "No text recognized" left it recording the room for hours, into files of over a gigabyte.
  Its wyoming-satellite is patched to reset openwakeword as soon as a transcript arrives, because unpatched it fed openwakeword the microphone while it played the done sound and ran the transcript command, before resetting it, so openwakeword, its window still ending in the wake word, woke again and aborted the answer to any request spoken more than 5 seconds, the satellite's refractory period, after the wake word.
  It is also patched to listen again, without the wake word, once a spoken reply ending in a question mark finishes playing, because Home Assistant's Wyoming integration ignores the follow-up its pipeline flags for such a reply, and Home Assistant hands that answer straight back to butler's voice lane in the same conversation.
  Its wake word also clears the panel's transcript, and its transcript and the text it is about to speak go to the panel through Home Assistant's `framer-voice` webhook.
  Each of its hook commands posts to spike in the background, because the satellite waits for a hook before it plays the next sound or reads the next event, which held the wake chime behind `panel-wake` and a request to spike.
  The mic stays open while the wake chime plays, instead of the satellite's default of muting it for the chime and half a second after, which cut the first words of every command.
  From the transcript until the reply starts playing, a soft tick repeats every 1.2 seconds through `pw-play` as the user unit `framer-thinking`, so a slow answer still shows it is being worked on; an error, a disconnect, a new wake or a dismissal stops it, and it stops itself after 60 seconds.
- Buttons (`modules/hosts/framer/voice.nix`, `buttons.py`): `framer-buttons.service` reads the clipboard's volume and power keys with python-evdev as `aaron` in the `input` group, without grabbing them.
  Volume up pressed twice within half a second dismisses the conversation: it stops the tick, kills the satellite's `aplay` so a reply stops mid-word, clears the panel and calls Home Assistant's `framer-dismiss` webhook.
  The power button stops the reply the same way but calls only `framer-assistant-toggle`, turning the assistant off or back on, since muting cancels Home Assistant's pipeline itself and a dismissal's reload would unload the mute switch under the toggle.
  `soc_button_array` exposes those keys only when it loads after `pinctrl_sunrisepoint`, the GPIO controller they hang off, so a modprobe `softdep` orders the two; loaded first, it gave up on them without a word.
  Before each start the satellite sets the speaker to full and the mic to `0.2` with `wpctl`, because at `1.0` the capture path's 60 dB of gain clipped the room's background noise, and a start before PipeWire is up keeps WirePlumber's saved volume instead of failing.
- `modules/hosts/framer/butler-browser-view.nix` runs `butler-browser-view.service` as `aaron`, polling spike's `https://browser.spike.cute.engineer/active` every 2 seconds and, while it reads `1`, opening a second `ungoogled-chromium` in kiosk mode on cage's Wayland display, on the view-only VNC spike serves framer alone, which cage shows in front of the dashboard until the service closes it again.
  framer resolves that name to `10.100.0.1` through its own `/etc/hosts`, because the home network's DNS hides private answers.
- framer runs no agent of its own: anything its Assist pipeline's own intents cannot answer goes to butler's voice endpoint on spike, and the mail, calendar, GitHub and backlogic tools OpenClaw once ran here are butler's, in `modules/hosts/spike/butler-tools.nix`.
- `modules/hosts/framer/panel.nix` runs `panel-remote.service`, which serves the kiosk's `panel` command over HTTP on `8124`, open on `wg0` alone, answering spike's `10.100.0.1` alone, for Home Assistant: `GET /brightness`, and `POST /on`, `/off`, `/schedule` and `/brightness/<percent>`.
- `node_exporter` is open on `wlp1s0` and `wg0`; `modules/hosts/spike/monitoring.nix` scrapes it as the `framer` target, beside spike's own.
- UEFI's Enable Battery Limit (Power + Volume Up at boot, Boot configuration, Advanced Options), present since the Surface Book 2's July 2020 firmware, holds both batteries at 50%; a hand step, since it is not something NixOS can set.
- A USB Ethernet adapter in the base beats the wifi for an always-on box; if one is used, its interface joins `modules/hosts/framer`'s firewall lists, a hand step alongside plugging it in.

### Neovim

`modules/neovim/lua`, `after/`, and `lazy-lock.json` are symlinked into `~/.config/nvim` with `mkOutOfStoreSymlink`, resolved through the `repoPath` option (relative to the home directory, default `workspace/jimbo`).

Lua edits take effect immediately without a rebuild; only `init.lua` and the LSP/tool packages in `default.nix` require a rebuild.

Lua is formatted with stylua (`stylua.toml` at repo root).

### Speed reading

`modules/speed-read` puts the Raycast script command Speed Read Selection in `~/.config/raycast/scripts` on the Macs, which copies the selection and plays it one word at a time from 500 wpm with agent-rsvp, at twice the Terminal profile's text size, in a Terminal window centred on the screen under the mouse pointer, after waiting for the hotkey's modifiers to be released so its copy keystroke reaches the app as a plain ⌘C.
On every switch it sets the default Terminal profile to close a window when its shell exits cleanly, so quitting the reader closes its window.
Adding that directory under Raycast's Script Commands and giving the command a hotkey are hand steps, since Raycast keeps both in its own database.

### WireGuard

`modules/wireguard` installs the WireGuard app from the App Store on the Macs.
On `pilot` its tunnel `Home network` is spike's peer `pilot`, imported by hand from `~/.config/wireguard/Home network.conf`, which holds its private key and never enters the repo.

### Claude Code

`modules/claude` writes the personal `CLAUDE.md`, skills and `settings.json` on every host.
Backlogic's plugin is on everywhere on the Linux hosts, and on the Macs nowhere but `pilot`'s backlogic checkouts.
Claude Code turns a plugin on for one repository only through that repository's settings, so on `pilot` every switch sets `backlogic@backlogic` in the gitignored `.claude/settings.local.json` of `~/workspace/backlogic`, each `~/workspace/backlogic--*` and each worktree under `~/workspace/backlogic/.claude/worktrees`, and a checkout made since the last switch has it from the next.
Every `pilot` session starts in ultracode, through `settings.json`'s `ultracode`.
On the Macs a `PreToolUse` hook, `pkill-guard.py`, refuses a Bash command running `pkill` or `pgrep` with an option after its pattern, because macOS takes every argument from the first pattern on as another pattern, and `pkill -f 'cat' -U $(id -u) -x` once signalled every process Aaron owned.
On the Macs `modules/cmux` appends to the personal `CLAUDE.md` a line pointing sessions that need a browser at cmux's, `cmux browser`, which holds a copy of Chromium's logins made with `cmux browser import`, since its WebKit view cannot use Chromium's profile itself.

### Other directories

- `voyager/`, QMK keymap for a ZSA Voyager keyboard; built/flashed externally with `qmk`, not part of the flake.
- `assets/`, static assets.

