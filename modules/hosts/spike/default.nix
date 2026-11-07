{
  host,
  lib,
  inputs,
  pkgs,
  ...
}:
{
  checks.${host.system} = {
    # The change probe end to end, with a local repository standing in for butler-memory.
    self-fix-probe =
      pkgs.runCommand "self-fix-probe-dry-run"
        {
          nativeBuildInputs = [
            pkgs.bash
            pkgs.git
            pkgs.python3
          ];
        }
        ''
          export HOME=$TMPDIR
          bash ${./butler-probe}/dry-run.sh > $out
        '';

    # The calendar's update and delete against a fake Home Assistant, its refusal of the work and muted calendars, the uid its reads print, and reminders' update and delete.
    butler-calendar =
      pkgs.runCommand "butler-calendar-test"
        {
          nativeBuildInputs = [
            pkgs.jq
            pkgs.tzdata
            (pkgs.python3.withPackages (ps: [ ps.pyicloud ]))
          ];
        }
        ''
          export HOME=$TMPDIR TZDIR=${pkgs.tzdata}/share/zoneinfo
          python3 ${./butler-calendar}/test_calendar.py ${./butler-calendar} ${./butler-reminders} > $out 2>&1 || { cat $out; exit 1; }
        '';

    # A change's start card and landed report card, and the start notice's fall back to text and the mood picture, on fixture briefs.
    change-cards =
      pkgs.runCommand "change-cards-test"
        {
          nativeBuildInputs = [
            pkgs.bash
            pkgs.jq
            pkgs.gnugrep
            pkgs.coreutils
          ];
        }
        ''
          bash ${./butler-self-fix}/test-cards.sh ${./butler-self-fix} > $out 2>&1 || { cat $out; exit 1; }
        '';

    # render's pictures by reference in a real Chromium: Butler's own load, and traversal, symlinks, file:// and the network are refused.
    butler-render =
      let
        source = pkgs.writeText "render.py" (
          import ./butler-render/source.nix { inherit pkgs lib; } {
            outbox = "/nonexistent/outbox";
            asset = "/nonexistent/asset";
            store = "/nonexistent/assets";
            scenes = "/nonexistent/scenes";
            sceneGroups = "general";
          }
        );
        python = pkgs.python3.withPackages (p: [
          p.playwright
          p.pillow
        ]);
      in
      pkgs.runCommand "butler-render-test" { nativeBuildInputs = [ python ]; } ''
        export HOME=$TMPDIR
        python3 -I ${./butler-render}/test_render.py ${source} > $out 2>&1 || { cat $out; exit 1; }
      '';

    # jimbo is public, so no picture of butler's branded work scenes may be in its source, and so in its store paths, by scene name or by the outbox file it came from.
    no-work-pictures =
      let
        scenes = (import ./butler-scenes-catalog.nix).work;
        sources = map (scene: scene.source) (lib.attrValues scenes);
      in
      pkgs.runCommand "no-work-pictures" { } ''
        found=$(find ${../../..} -type f \( -false ${
          lib.concatMapStrings (source: "-o -name ${lib.escapeShellArg source} ") sources
        }${
          lib.concatMapStrings (name: "-o -iname ${lib.escapeShellArg "${name}.*"} ") (lib.attrNames scenes)
        }\) \( -iname '*.webp' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.gif' -o -iname '*.svg' -o -iname '*.avif' -o -iname '*.heic' \))
        if [ -n "$found" ]; then
          echo "pictures of butler's work scenes are in public jimbo:" >&2
          echo "$found" >&2
          exit 1
        fi
        [ ${toString (builtins.length sources)} -gt 0 ] || { echo "the work scene list is empty, so this checks nothing" >&2; exit 1; }
        echo ok > $out
      '';

    # Aaron dropped the head butler's name of 5 Nov 2026 on 6 Nov, so it may not come back into the bot's configuration or these docs; spelt in halves so this check does not find itself.
    no-old-head-name =
      let
        old = "Wads" + "worth";
      in
      pkgs.runCommand "no-old-head-name" { nativeBuildInputs = [ pkgs.gnugrep ]; } ''
        if grep -rIni ${lib.escapeShellArg old} ${../../..}/modules ${../../../.claude/CLAUDE.md} ${./CLAUDE.md}; then
          echo "the dropped head butler name is back in jimbo" >&2
          exit 1
        fi
        echo ok > $out
      '';

    # The backlogic sweep's notices: silent seeding, the runner down and back once each, the daily waiting notice.
    backlogic-sweep =
      pkgs.runCommand "backlogic-sweep-notify" { nativeBuildInputs = [ pkgs.python3 ]; }
        ''
          python3 -I ${./backlogic-sweep}/test_sweep.py > $out 2>&1 || { cat $out; exit 1; }
        '';

    # The landing queue's holds, cues and releases, with a fake clock and call.
    land-queue = pkgs.runCommand "land-queue-dry-run" { nativeBuildInputs = [ pkgs.python3 ]; } ''
      python3 ${./butler-land}/test_land.py > $out 2>&1 || { cat $out; exit 1; }
    '';

    # The machines monitor's thresholds, holds, suppression, expected-off marks, escalation, quiet hours and action choice, on fake machines.
    butler-monitor =
      let
        config = pkgs.writeText "butler-monitor-test.json" (
          builtins.toJSON {
            inherit (import ./butler-monitor/defaults.nix) thresholds quiet remediation;
            alwaysOn = [
              "spike"
              "framer"
            ];
            keepAwakeHosts = [
              "piggys-MBP"
              "jimbo"
            ];
            readOnlyHosts = [ "pilot" ];
            failStreaks."backlogic-switch.service" = {
              file = "/nonexistent";
              runs = 3;
              stuckMinutes = 10;
            };
            keepGenerations = 5;
            hosts = { };
            prometheusHosts = [
              "spike"
              "framer"
            ];
          }
        );
      in
      pkgs.runCommand "butler-monitor-test" { nativeBuildInputs = [ pkgs.python3 ]; } ''
        python3 ${./butler-monitor/test_monitor.py} ${./butler-monitor/monitor.py} ${config} > $out 2>&1 || { cat $out; exit 1; }
      '';

    # pulse's root channel over a scratch spool, a fake systemctl and a fake Mac: only allowlisted actions on allowlisted,
    # unprotected targets, both kill switches, its own hourly ceiling, a stamp unblocked and never deleted, caches alone.
    pulse-reflex-act = pkgs.runCommand "pulse-reflex-act-test" { nativeBuildInputs = [ pkgs.python3 pkgs.bash pkgs.findutils pkgs.gawk ]; } ''
      python3 -I ${./pulse-reflex/test_act.py} ${./pulse-reflex/act.py} ${./pulse-reflex/mac-free-disk.sh} > $out 2>&1 || { cat $out; exit 1; }
    '';

    # The Work in flight snapshot from fixture change records, offline, checking nothing private or path-shaped gets out.
    butler-work =
      let
        strip =
          name:
          builtins.replaceStrings [ "if __name__ == '__main__':\n    sys.exit(${name}(sys.argv))\n" ] [ "" ];
        source =
          builtins.replaceStrings
            [ "@selfFix@" "@kanban@" "@git@" "@limits@" ]
            [ "/nonexistent" "/nonexistent" "git" "/nonexistent" ]
            (
              strip "main" (builtins.readFile ./butler-builders/builders.py)
              + strip "work_main" (builtins.readFile ./butler-builders/work.py)
              + builtins.readFile ./butler-builders/work-test.py
            );
        test = pkgs.writers.writePython3Bin "butler-work-test" {
          flakeIgnore = [
            "E501"
            "E402"
            "E302"
            "E303"
            "E305"
          ];
        } source;
      in
      pkgs.runCommand "butler-work-test" { } ''
        mkdir $out
        ${lib.getExe test} $out/work.json
      '';

    # mac's presence notes: who else used a machine lately, and whether Aaron's own keyboard or mouse is on it.
    butler-mac-presence =
      pkgs.runCommand "butler-mac-presence-test" { nativeBuildInputs = [ pkgs.python3 ]; }
        ''
          python3 -I ${./butler-mac/test_presence.py} ${./butler-mac/presence.py} > $out 2>&1 || { cat $out; exit 1; }
        '';

    # mac push: a file butler may attach lands in a fake Mac's ~/butler-drop, secrets and uncleared sensitive documents are refused, and a sensitive copy is deleted after its time.
    butler-mac-push =
      pkgs.runCommand "butler-mac-push-test" { nativeBuildInputs = [ pkgs.python3 ]; }
        ''
          python3 -I ${./butler-mac/test_push.py} ${./butler-mac/push.py} > $out 2>&1 || { cat $out; exit 1; }
        '';

    # kanban's thread links: a change's thread, a started session's parent and the thread cards sent to the board, offline.
    butler-kanban = pkgs.runCommand "butler-kanban-test" { nativeBuildInputs = [ pkgs.python3 ]; } ''
      python3 -I ${./butler-kanban/test_kanban.py} ${./butler-kanban/kanban.py} > $out 2>&1 || { cat $out; exit 1; }
    '';

    # The live integration check offline: coverage names real checks, secrets never reach a cause or an alert, alerts go out once and never for a source not connected, the writers' gates judged from a manifest, and checks against fake services.
    butler-integrations =
      let
        coverage = pkgs.writeText "butler-integrations-coverage.json" (
          builtins.toJSON (import ./butler-integrations/coverage.nix)
        );
      in
      pkgs.runCommand "butler-integrations-test" { nativeBuildInputs = [ pkgs.python3 ]; } ''
        python3 -I ${./butler-integrations/test_check.py} ${./butler-integrations/check.py} ${coverage} > $out 2>&1 || { cat $out; exit 1; }
      '';

    # The Threads snapshot from a fixture threads.db, checking kinds, states and that no message text gets out.
    butler-threads = pkgs.runCommand "butler-threads-test" { nativeBuildInputs = [ pkgs.python3 ]; } ''
      python3 -I ${./butler-threads/test_threads.py} ${./butler-threads/threads.py} > $out 2>&1 || { cat $out; exit 1; }
    '';

    # The Slack reader against a fake Slack: long messages, threads past a page, shared messages, unfurls and file text whole, the token kept to Slack's hosts.
    butler-slack = pkgs.runCommand "butler-slack-test" { nativeBuildInputs = [ pkgs.python3 ]; } ''
      python3 -I ${./butler-slack/test_slack.py} ${./butler-slack/slack.py} > $out 2>&1 || { cat $out; exit 1; }
    '';

    # slack-send against a fake Slack: each verb's one method and exact text, edits and deletes of Butler's own messages alone, the approval-size limit, the audit spool and the rate limit.
    butler-slack-send = pkgs.runCommand "slack-send-test" { nativeBuildInputs = [ pkgs.python3 ]; } ''
      python3 -I ${./butler-slack/test_send.py} ${./butler-slack/send.py} > $out 2>&1 || { cat $out; exit 1; }
    '';

    # The chat cache from a fixture index and live feeds: normalisation, conversation kinds, contacts and who is waiting on Aaron.
    butler-chat = pkgs.runCommand "butler-chat-test" { nativeBuildInputs = [ pkgs.python3 ]; } ''
      python3 -I ${./butler-chat/test_chat.py} ${./butler-chat/chat.py} > $out 2>&1 || { cat $out; exit 1; }
    '';

    # The live feeds against fixture RSS, Spotify, Steam, PayPal and mail answers, writing the index inbox's shapes offline.
    butler-feeds = pkgs.runCommand "butler-feeds-test" { nativeBuildInputs = [ pkgs.python3 ]; } ''
      python3 -I ${./butler-feeds/test_feeds.py} ${./butler-feeds/feeds.py} > $out 2>&1 || { cat $out; exit 1; }
    '';

    # The work Google reader against a mock Google: refresh, mail listings, reading, the calendar's filters, and that it never asks for more than read-only scopes.
    butler-work-google =
      pkgs.runCommand "butler-work-google-test" { nativeBuildInputs = [ pkgs.python3 ]; }
        ''
          python3 -I ${./butler-work-google/test_work_google.py} ${./butler-work-google/work_google.py} ${pkgs.tzdata}/share/zoneinfo > $out 2>&1 || { cat $out; exit 1; }
        '';

    # The context packs from fixture memory, a fake board and a fake pilot, checking nothing private reaches one.
    butler-context = pkgs.runCommand "butler-context-test" { nativeBuildInputs = [ pkgs.python3 ]; } ''
      python3 -I ${./butler-context/test_context.py} ${./butler-context/context.py} > $out 2>&1 || { cat $out; exit 1; }
    '';

    # butler's `note` and butler-notes-write against a scratch vault offline: reads, writes, stale-edit refusals, history, restore and paths.
    butler-notes =
      let
        built = import ./butler-notes/packages.nix {
          inherit pkgs lib;
          ob = "/nonexistent";
        };
      in
      pkgs.runCommand "butler-notes-test" { nativeBuildInputs = [ pkgs.git ]; } ''
        HOME=$TMPDIR bash ${./butler-notes/test_notes.sh} ${lib.getExe built.note} ${lib.getExe built.writer} > $out 2>&1 || { cat $out; exit 1; }
      '';

    # The device gate's login, cookies, expiry, lockout and redirects over HTTP.
    device-gate = pkgs.runCommand "device-gate-test" { nativeBuildInputs = [ pkgs.python3 ]; } ''
      cp ${./device-gate}/gate.py ${./device-gate}/test.py .
      python3 -I test.py > $out
    '';
  };

  nixosSystemModule =
    { pkgs, config, ... }:
    {
      imports = [
        ./hardware.nix
        ./backlogic.nix
        ./backlogic-tunnel.nix
        ./backlogic-sweep.nix
        ./bowerbird.nix
        ./butler.nix
        ./butler-backlogic-source.nix
        ./butler-chat.nix
        ./butler-browser.nix
        ./butler-builders.nix
        ./butler-context.nix
        ./butler-work.nix
        ./butler-threads.nix
        ./butler-drive.nix
        ./butler-feeds.nix
        ./butler-health.nix
        ./butler-assets.nix
        ./butler-imagine.nix
        ./butler-inbox.nix
        ./butler-integrations.nix
        ./butler-voice-sample.nix
        ./butler-jobs.nix
        ./butler-kanban.nix
        ./butler-land.nix
        inputs.butler.nixosModules.index
        ./butler-mac.nix
        ./butler-mail.nix
        ./butler-maps.nix
        ./butler-mindbody.nix
        ./butler-notes.nix
        ./butler-messenger.nix
        ./butler-monitor.nix
        ./pulse-reflex.nix
        ./butler-overlay-relay.nix
        ./butler-notify.nix
        ./butler-outlook.nix
        ./butler-photos.nix
        ./butler-remarkable.nix
        ./butler-reminders.nix
        ./butler-render.nix
        ./butler-scenes.nix
        ./butler-probe.nix
        ./pulse.nix
        ./butler-self-fix.nix
        ./butler-selfcheck.nix
        ./butler-shell.nix
        ./butler-slack.nix
        ./butler-tools.nix
        ./butler-up.nix
        ./butler-voice.nix
        ./butler-weather.nix
        ./butler-work-google.nix
        ./caddy.nix
        ./claude.nix
        ./device-gate.nix
        ./kanban.nix
        ./kanban-remote.nix
        ./dns.nix
        ./docker.nix
        ./environments.nix
        ./framer-vnc.nix
        ./github.nix
        ./home-assistant.nix
        ./messenger.nix
        ./mise.nix
        ./monitoring.nix
        ./voice.nix
        ./watchdog.nix
        ./remote-builder.nix
        ./remote-desk.nix
        ./tmp.nix
        ./wireguard.nix
      ];

      butler.imagine.enable = true;
      butler.credentialedTools = true;
      butler.voice.enable = true;
      butler.drive.enable = true;
      butler.inbox.enable = true;
      butler.garmin.enable = true;
      butler.outlook = {
        enable = true;
        address = "aaronpierce@outlook.com.au";
      };
      butler.hevy.enable = true;
      # The bridge's Facebook login lapsed on 5 Nov 2026; until `sudo messenger-setup` logs it in again, reads show the history it kept and every send says Messenger refused it.
      butler.messenger.enable = true;
      # Read-only; nothing is read until Aaron runs `sudo -u butler butler-work-google-login <work address>` on spike.
      butler.workGoogle.enable = true;
      butler.remarkable.enable = true;
      butler.index.captions.photosScript = ./butler-photos/photos.py;
      # Butler's mood pictures, for the Daily tab and the picture of it DMed each morning.
      butler.index.daily.moods = ../../../assets/butler/moods;
      # The index holds Aaron's payments, messages and more, so a thread that searched it counts as having read private data.
      butler.commands.life.private = true;
      # Every read-only verb runs in every lane, the board's and calls' included, with the options life.py takes; the private flake's own rules allowed no option, so every search with --from or --limit was refused.
      # A spoken result that used it still asks before framer says it, since the command is private.
      butler.commands.life.rules =
        let
          lanes = [
            "interactive"
            "voice"
            "cron"
            "call"
          ];
        in
        lib.mkForce (
          [
            {
              match = [ "sources" ];
              inherit lanes;
            }
          ]
          ++
            map
              (verb: {
                match = [
                  verb
                  "**"
                ];
                inherit lanes;
                flags = [
                  "--from"
                  "--to"
                  "--source"
                  "--kind"
                  "--limit"
                ];
              })
              [
                "search"
                "day"
                "spending"
                "photos"
              ]
        );
      butler.index.browserHistory.devices.pilot = {
        address = "10.100.0.11";
        keys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGtqizfD3BqSqW9So42zNpzbxV5/F8W9CvQsOELTPdfe browser-history@pilot"
        ];
      };
      butler.index.browserHistory.devices.piggysmbp = {
        address = "10.100.0.2";
        keys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIL4wbVpgW/cFXIcx+z0PLq5CBPMYVbW5Z+yVSBYo621F browser-history@piggysmbp"
        ];
      };

      boot.loader.systemd-boot.enable = true;
      boot.loader.systemd-boot.configurationLimit = config.jimbo.keepGenerations;
      boot.loader.efi.canTouchEfiVariables = true;

      networking.hostName = host.hostname;

      users.users.${host.username}.openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKMkmFNbJsrIYrkDs5/1OO9lIOU/ZDiDVvHs8kR8Rq7K"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFTgNyfuTRL/Kygs5zNODcjMpcT/69U91T7nrOOHrbju"
      ];

      users.users.rylee = {
        isNormalUser = true;
        description = "Rylee";
        extraGroups = [
          "wheel"
          "docker"
        ];
        openssh.authorizedKeys.keys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICajNcJKs5Iv63ZNppww4tNmNjkMjbPJwX2trSPiLGeT"
        ];
      };

      nix.gc.dates = "daily";

      programs.git.enable = true;

      environment.systemPackages = [ pkgs.vim ];

      services.openssh.settings.PasswordAuthentication = false;

      services.avahi = {
        enable = true;
        openFirewall = true;
        # Over IPv6 avahi took its own announcement for a conflict and renamed
        # spike `spike-2.local`, and framer's kiosk, waiting for `spike.local`,
        # never opened its page again; https://github.com/avahi/avahi/issues/117
        settings.server.use-ipv6 = false;
        settings.publish = {
          disable-publishing = false;
          publish-addresses = true;
        };
      };

      # A rename that happens anyway lasts until avahi restarts, so take the name back.
      systemd.services.avahi-keep-name = {
        description = "Restart avahi when it has renamed spike after a name conflict";
        after = [ "avahi-daemon.service" ];
        serviceConfig.Type = "oneshot";
        path = [
          pkgs.systemd
          pkgs.gnused
        ];
        script = ''
          systemctl is-active --quiet avahi-daemon.service || exit 0
          name=$(busctl --system call org.freedesktop.Avahi / org.freedesktop.Avahi.Server GetHostName | sed -n 's/^s "\(.*\)"$/\1/p')
          if [ -n "$name" ] && [ "$name" != ${lib.escapeShellArg config.networking.hostName} ]; then
            echo "avahi calls spike $name.local, restarting it to take ${config.networking.hostName}.local back"
            systemctl restart avahi-daemon.service
          fi
        '';
      };

      systemd.timers.avahi-keep-name = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "2min";
          OnUnitActiveSec = "1min";
        };
      };

      systemd.targets = {
        sleep.enable = false;
        suspend.enable = false;
        hibernate.enable = false;
        hybrid-sleep.enable = false;
      };

      zramSwap.enable = true;

      services.journald.settings.Journal.SystemMaxUse = "1G";

      system.stateVersion = "26.05";
    };

  nixosHomeModule.home.stateVersion = "26.11";
  nixosHomeModule.home.file = lib.genAttrs [ ".claude/CLAUDE.md" ".claude-work/CLAUDE.md" ] (_: {
    text = lib.mkAfter (builtins.readFile ./CLAUDE.md);
  });
}
