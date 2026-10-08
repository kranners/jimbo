{
  lib,
  config,
  host,
  ...
}:
let
  inherit (lib) mkOption types;

  timeOfDay = types.strMatching "([01][0-9]|2[0-3]):[0-5][0-9]";
  brightnessPercent = types.ints.between 0 100;

  cfg = config.kiosk;
in
{
  options.kiosk = {
    url = mkOption {
      description = "Address the kiosk browser opens full screen.";
      type = types.str;
    };

    lanInterface = mkOption {
      description = "Network interface, besides wg0, the panel's VNC ports are reachable from.";
      type = types.str;
    };

    schedule = mkOption {
      description = "Times of day the panel's backlight steps to a new level.";
      type = types.listOf (
        types.submodule {
          options = {
            time = mkOption {
              description = "Time of day, HH:MM, the level below takes effect.";
              type = timeOfDay;
            };

            percent = mkOption {
              description = "Backlight level the panel steps to at this time.";
              type = brightnessPercent;
            };
          };
        }
      );
      default = [
        {
          time = "07:30";
          percent = 60;
        }
        {
          time = "18:00";
          percent = 15;
        }
        {
          time = "23:30";
          percent = 0;
        }
        {
          time = "06:30";
          percent = 15;
        }
      ];
    };
  };

  config.nixosSystemModule =
    { pkgs, ... }:
    let
      sortedSchedule = lib.sort (a: b: a.time < b.time) cfg.schedule;
      wrapPercent = (lib.last sortedSchedule).percent;
      dayPercent = lib.foldl' lib.max 0 (map (entry: entry.percent) cfg.schedule);
      timeDigits = time: lib.replaceStrings [ ":" ] [ "" ] time;
      brightness = config.brightness.command;

      panelScheduleApply = pkgs.writeShellApplication {
        name = "panel-schedule-apply";
        runtimeInputs = [ pkgs.coreutils ];
        text = ''
          now=$((10#$(date +%H%M)))
          percent=${toString wrapPercent}
          ${lib.concatMapStrings (entry: ''
            if [ "$now" -ge $((10#${timeDigits entry.time})) ]; then
              percent=${toString entry.percent}
            fi
          '') sortedSchedule}
          ${brightness} set "$percent"
        '';
      };

      panelWake = pkgs.writeShellApplication {
        name = "panel-wake";
        runtimeInputs = [ pkgs.systemd ];
        text = ''
          ${brightness} set ${toString dayPercent}
          systemd-run --unit=panel-wake-restore --on-active=2min -- ${lib.getExe panelScheduleApply}
        '';
      };

      kioskPanel = pkgs.writeShellApplication {
        name = "kiosk-panel";
        runtimeInputs = [
          pkgs.wayvnc
          pkgs.ungoogled-chromium
        ];
        text = ''
          wayvnc 0.0.0.0 5900 &
          trap 'kill $!' EXIT
          exec chromium \
            --kiosk \
            --ozone-platform=wayland \
            --force-device-scale-factor=2 \
            --noerrdialogs \
            --disable-session-crashed-bubble \
            --disable-infobars \
            ${cfg.url}
        '';
      };

      kioskRemoteView = pkgs.writeShellApplication {
        name = "kiosk-remote-view";
        runtimeInputs = [ pkgs.python3Packages.websockify ];
        text = ''
          exec websockify --web ${pkgs.novnc}/share/webapps/novnc 6080 localhost:5900
        '';
      };

      scheduleServices = lib.listToAttrs (
        map (entry: {
          name = "panel-brightness-${timeDigits entry.time}";
          value = {
            description = "Step the panel's backlight to ${toString entry.percent}% for ${entry.time}";
            serviceConfig = {
              Type = "oneshot";
              ExecStart = "${brightness} set ${toString entry.percent}";
            };
          };
        }) cfg.schedule
      );

      scheduleTimers = lib.listToAttrs (
        map (entry: {
          name = "panel-brightness-${timeDigits entry.time}";
          value = {
            wantedBy = [ "timers.target" ];
            timerConfig = {
              OnCalendar = entry.time;
              Persistent = true;
            };
          };
        }) cfg.schedule
      );
    in
    {
      services.cage = {
        enable = true;
        user = host.username;
        program = lib.getExe kioskPanel;
      };

      systemd.services = scheduleServices // {
        cage-tty1.serviceConfig.Restart = "always";

        kiosk-remote-view = {
          description = "Panel noVNC bridge to wayvnc";
          wantedBy = [ "graphical.target" ];
          after = [ "cage-tty1.service" ];
          serviceConfig = {
            ExecStart = lib.getExe kioskRemoteView;
            Restart = "always";
            RestartSec = 5;
          };
        };
      };

      systemd.timers = scheduleTimers;

      environment.systemPackages = [ panelWake ];

      networking.firewall.interfaces = lib.genAttrs [ cfg.lanInterface "wg0" ] (_: {
        allowedTCPPorts = [
          5900
          6080
        ];
      });

      systemd.targets = {
        sleep.enable = false;
        suspend.enable = false;
        hibernate.enable = false;
        hybrid-sleep.enable = false;
      };

      services.logind.settings.Login = {
        HandleLidSwitch = "ignore";
        HandleLidSwitchExternalPower = "ignore";
        HandleLidSwitchDocked = "ignore";
        HandlePowerKey = "ignore";
      };
    };
}
