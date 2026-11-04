{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.nuc.watchdog;

  # Runs every minute: spike counts as up while it answers ping or its Grafana health check over WireGuard, and,
  # when heartbeatUrl is set, while butler-monitor's last run is under 10 minutes old.
  # Once it has been down downMinutes, it says so once, and again when it is back.
  # butler-notify, the way everything else reaches Aaron, lives on spike, so it cannot carry this:
  # the notice goes to the journal at crit, and to a Discord webhook when Aaron has written one in webhookFile.
  spike-watchdog = pkgs.writeShellApplication {
    name = "spike-watchdog";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.curl
      pkgs.gnused
      pkgs.iputils
      pkgs.jq
      pkgs.util-linux
    ];
    text = ''
      down_since="$STATE_DIRECTORY/down-since"
      told="$STATE_DIRECTORY/told"
      now=$(date +%s)

      tell() {
        logger -p daemon.crit -t spike-watchdog "$1"
        if [ -s ${cfg.webhookFile} ]; then
          jq -n --arg content "$1" '{content: $content}' \
            | curl -fsS --max-time 20 -H 'Content-Type: application/json' --data @- "$(cat ${cfg.webhookFile})" >/dev/null \
            || echo "spike-watchdog: the Discord webhook refused the notice" >&2
        fi
      }

      up=""
      reason="spike answers neither ping nor Grafana over WireGuard"
      if ping -c 1 -W 3 10.100.0.1 >/dev/null 2>&1 \
        || curl -fsS --max-time 10 --resolve grafana.spike.cute.engineer:443:10.100.0.1 \
          https://grafana.spike.cute.engineer/api/health >/dev/null 2>&1; then
        up=yes
      fi
      ${lib.optionalString (cfg.heartbeatUrl != null) ''
        if [ -n "$up" ]; then
          last=$(curl -fsS --max-time 10 ${lib.escapeShellArg cfg.heartbeatUrl} \
            | sed -n 's/^butler_monitor_last_run_timestamp_seconds \([0-9.e+]*\)$/\1/p' | head -n 1)
          if [ -z "$last" ] || [ "$(( now - $(printf '%.0f' "$last") ))" -gt 600 ]; then
            up=""
            reason="spike answers, but butler-monitor has not finished a run in 10 minutes"
          fi
        fi
      ''}

      if [ -n "$up" ]; then
        if [ -e "$told" ]; then
          since=$(cat "$down_since")
          tell "spike is back after $(( (now - since) / 60 )) minutes down."
        fi
        rm -f "$down_since" "$told"
        exit 0
      fi

      [ -e "$down_since" ] || echo "$now" > "$down_since"
      since=$(cat "$down_since")
      if [ ! -e "$told" ] && [ "$(( now - since ))" -ge ${toString (cfg.downMinutes * 60)} ]; then
        tell "spike has been down for $(( (now - since) / 60 )) minutes: $reason. Butler is off until it is back."
        touch "$told"
      fi
    '';
  };
in
{
  options.nuc.watchdog = {
    enable = lib.mkEnableOption "an off-box watchdog that tells Aaron when spike has been unreachable over WireGuard for a while";

    downMinutes = lib.mkOption {
      description = "How long spike must be unreachable before the watchdog says so.";
      type = lib.types.ints.positive;
      default = 10;
    };

    heartbeatUrl = lib.mkOption {
      description = ''
        A node_exporter metrics URL carrying butler_monitor_last_run_timestamp_seconds, such as spike's
        http://10.100.0.1:9100/metrics, which spike's firewall closes on wg0 today, so it is null until Aaron opens it to the NUC.
      '';
      type = lib.types.nullOr lib.types.str;
      default = null;
    };

    webhookFile = lib.mkOption {
      description = "A file holding a Discord webhook URL, written by hand, mode 600; while it is missing or empty, notices go to the journal alone.";
      type = lib.types.str;
      default = "/var/lib/secrets/spike-watchdog-webhook";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.spike-watchdog = {
      description = "Check spike is reachable over WireGuard and tell Aaron when it is not";
      after = [ "wireguard-wg0.service" ];
      serviceConfig = {
        Type = "oneshot";
        StateDirectory = "spike-watchdog";
        ExecStart = lib.getExe spike-watchdog;
      };
    };

    systemd.timers.spike-watchdog = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "2min";
        OnUnitActiveSec = "1min";
      };
    };
  };
}
