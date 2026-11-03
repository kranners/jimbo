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

    # The landing queue's holds, cues and releases, with a fake clock and call.
    land-queue = pkgs.runCommand "land-queue-dry-run" { nativeBuildInputs = [ pkgs.python3 ]; } ''
      python3 ${./butler-land}/test_land.py > $out 2>&1 || { cat $out; exit 1; }
    '';

    # The machines monitor's thresholds, holds, repeats, quiet hours and action choice, on fake machines.
    butler-monitor =
      let
        config = pkgs.writeText "butler-monitor-test.json" (
          builtins.toJSON {
            inherit (import ./butler-monitor/defaults.nix) thresholds quiet;
            alwaysOn = [
              "spike"
              "framer"
            ];
            keepAwakeHosts = [
              "piggys-MBP"
              "jimbo"
            ];
            readOnlyHosts = [ "pilot" ];
            restartable = "butler-[a-z0-9-]+\\.service";
            neverRestart = [ "butler.service" ];
            keepGenerations = 5;
            journalVacuum = "500M";
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
  };

  nixosSystemModule =
    { pkgs, ... }:
    {
      imports = [
        ./hardware.nix
        ./backlogic.nix
        ./backlogic-tunnel.nix
        ./backlogic-sweep.nix
        ./bowerbird.nix
        ./butler.nix
        ./butler-backlogic-source.nix
        ./butler-browser.nix
        ./butler-builders.nix
        ./butler-work.nix
        ./butler-drive.nix
        ./butler-health.nix
        ./butler-imagine.nix
        ./butler-voice-sample.nix
        ./butler-jobs.nix
        ./butler-kanban.nix
        ./butler-land.nix
        inputs.butler.nixosModules.index
        ./butler-mac.nix
        ./butler-mail.nix
        ./butler-maps.nix
        ./butler-messenger.nix
        ./butler-monitor.nix
        ./butler-notify.nix
        ./butler-outlook.nix
        ./butler-photos.nix
        ./butler-remarkable.nix
        ./butler-reminders.nix
        ./butler-render.nix
        ./butler-probe.nix
        ./butler-self-fix.nix
        ./butler-shell.nix
        ./butler-slack.nix
        ./butler-tools.nix
        ./butler-up.nix
        ./butler-voice.nix
        ./butler-weather.nix
        ./caddy.nix
        ./claude.nix
        ./dns.nix
        ./docker.nix
        ./environments.nix
        ./framer-vnc.nix
        ./home-assistant.nix
        ./messenger.nix
        ./mise.nix
        ./monitoring.nix
        ./voice.nix
        ./watchdog.nix
        ./remote-builder.nix
        ./tmp.nix
        ./wireguard.nix
      ];

      butler.imagine.enable = true;
      butler.credentialedTools = true;
      butler.voice.enable = true;
      butler.drive.enable = true;
      butler.garmin.enable = true;
      butler.outlook = {
        enable = true;
        address = "aaronpierce@outlook.com.au";
      };
      butler.hevy.enable = true;
      butler.remarkable.enable = true;
      butler.index.captions.photosScript = ./butler-photos/photos.py;
      # The index holds Aaron's payments, messages and more, so a thread that searched it counts as having read private data.
      butler.commands.life.private = true;
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
