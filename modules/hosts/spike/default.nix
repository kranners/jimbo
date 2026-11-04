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

    # jimbo is public, so no picture of butler's Work-branded Work notes scenes may be in its source, and so in its store paths, by name or by the outbox file it came from.
    no-work-notes-pictures =
      let
        sources = map (scene: scene.source) (lib.attrValues (import ./butler-scenes-catalog.nix).work-notes);
      in
      pkgs.runCommand "no-work-notes-pictures" { } ''
        found=$(find ${../../..} -type f \( -iname '*work-notes*' -o -iname '*work*' ${
          lib.concatMapStrings (source: "-o -name ${lib.escapeShellArg source} ") sources
        }\) \( -iname '*.webp' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.gif' -o -iname '*.svg' -o -iname '*.avif' -o -iname '*.heic' \))
        if [ -n "$found" ]; then
          echo "pictures of Work's Work notes scenes are in public jimbo:" >&2
          echo "$found" >&2
          exit 1
        fi
        [ ${toString (builtins.length sources)} -gt 0 ] || { echo "the Work notes scene list is empty, so this checks nothing" >&2; exit 1; }
        echo ok > $out
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

    # The Threads snapshot from a fixture threads.db, checking kinds, states and that no message text gets out.
    butler-threads = pkgs.runCommand "butler-threads-test" { nativeBuildInputs = [ pkgs.python3 ]; } ''
      python3 -I ${./butler-threads/test_threads.py} ${./butler-threads/threads.py} > $out 2>&1 || { cat $out; exit 1; }
    '';

    # The chat cache from a fixture index and live feeds: normalisation, conversation kinds, contacts and who is waiting on Aaron.
    butler-chat = pkgs.runCommand "butler-chat-test" { nativeBuildInputs = [ pkgs.python3 ]; } ''
      python3 -I ${./butler-chat/test_chat.py} ${./butler-chat/chat.py} > $out 2>&1 || { cat $out; exit 1; }
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
        ./butler-health.nix
        ./butler-imagine.nix
        ./butler-inbox.nix
        ./butler-voice-sample.nix
        ./butler-jobs.nix
        ./butler-kanban.nix
        ./butler-land.nix
        inputs.butler.nixosModules.index
        ./butler-mac.nix
        ./butler-mail.nix
        ./butler-maps.nix
        ./butler-mindbody.nix
        ./butler-messenger.nix
        ./butler-monitor.nix
        ./butler-overlay-relay.nix
        ./butler-notify.nix
        ./butler-outlook.nix
        ./butler-photos.nix
        ./butler-remarkable.nix
        ./butler-reminders.nix
        ./butler-render.nix
        ./butler-scenes.nix
        ./butler-probe.nix
        ./butler-self-fix.nix
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
      # Read-only; nothing is read until Aaron runs `sudo -u butler butler-work-google-login` on spike.
      butler.workGoogle = {
        enable = true;
        address = "me@example.com";
      };
      butler.remarkable.enable = true;
      butler.index.captions.photosScript = ./butler-photos/photos.py;
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
        settings.publish = {
          disable-publishing = false;
          publish-addresses = true;
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
