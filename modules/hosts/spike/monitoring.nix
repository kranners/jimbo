{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.services) cadvisor grafana prometheus;
  grafanaSecretKey = "${grafana.dataDir}/secret_key";
  grafanaBacklogicToken = "${grafana.dataDir}/backlogic-token";
  grafanaDiscordWebhook = "${grafana.dataDir}/discord-webhook";
  # Grafana refuses to start while a Discord contact point's URL is empty, so an unwritten webhook points nowhere instead.
  unsetDiscordWebhook = "http://127.0.0.1:9/discord-webhook-unset";
  backlogicUrl = "http://127.0.0.1:4200";
  grafanaDomain = "grafana.spike.cute.engineer";
  textfileDir = "/var/lib/claude-limits";

  # Grafana fails to provision a datasource whose uid changed, so this is the one it derived from the name "Prometheus".
  prometheusUid = "PBFA97CFB590B2093";
  discordContactPoint = "Discord";

  alertThresholds = {
    recentBootSeconds = 30 * 60;
    minAvailableMebibytes = 1536;
    maxSwapUsed = 0.8;
    maxRootInodesUsed = 0.8;
    maxServiceRestartsPerHour = 3;
  };

  above = threshold: {
    type = "gt";
    params = [ threshold ];
  };
  below = threshold: {
    type = "lt";
    params = [ threshold ];
  };
  percent = fraction: "${toString (builtins.floor (fraction * 100))}%";

  alertRule =
    {
      uid,
      title,
      summary,
      expr,
      evaluator,
      for ? "0s",
    }:
    {
      inherit uid title for;
      condition = "threshold";
      data = [
        {
          refId = "query";
          datasourceUid = prometheusUid;
          relativeTimeRange = {
            from = 600;
            to = 0;
          };
          model = {
            refId = "query";
            inherit expr;
            instant = true;
          };
        }
        {
          refId = "threshold";
          datasourceUid = "__expr__";
          model = {
            refId = "threshold";
            type = "threshold";
            expression = "query";
            conditions = [ { inherit evaluator; } ];
          };
        }
      ];
      noDataState = "OK";
      execErrState = "Error";
      annotations.summary = summary;
    };

  # Reads the undocumented endpoint behind Claude Code's /usage, with the token Claude Code keeps refreshed.
  claudeLimits = pkgs.writeShellApplication {
    name = "claude-limits";
    runtimeInputs = [
      pkgs.curl
      pkgs.jq
    ];
    text = ''
      token=$(jq -r .claudeAiOauth.accessToken ~/.claude/.credentials.json)
      curl --silent --fail https://api.anthropic.com/api/oauth/usage \
        --header "Authorization: Bearer $token" \
        --header "anthropic-beta: oauth-2025-04-20" |
        jq -r -f ${./claude-limits.jq} > ${textfileDir}/claude-limits.prom.tmp
      mv ${textfileDir}/claude-limits.prom.tmp ${textfileDir}/claude-limits.prom
    '';
  };
in
{
  imports = [ ./dashboards.nix ];

  # Docker runs its own containerd, so point cAdvisor at it to label containers by name and image.
  services.cadvisor = {
    enable = true;
    extraOptions = [ "--containerd=/run/docker/containerd/containerd.sock" ];
  };

  services.prometheus = {
    enable = true;

    # Accepts Claude Code telemetry at /api/v1/otlp/v1/metrics.
    extraFlags = [
      "--web.enable-otlp-receiver"
      "--enable-feature=created-timestamp-zero-ingestion"
    ];

    globalConfig.scrape_interval = "1m";
    retentionTime = "1y";

    exporters.node = {
      enable = true;
      enabledCollectors = [ "systemd" ];
      extraFlags = [
        "--collector.textfile.directory=${textfileDir}"
        "--collector.systemd.enable-restarts-metrics"
      ];
    };

    scrapeConfigs = [
      {
        job_name = "node";
        static_configs = [
          {
            targets = [ "localhost:${toString prometheus.exporters.node.port}" ];
            labels.host = "spike";
          }
          {
            targets = [ "10.100.0.5:9100" ];
            labels.host = "framer";
          }
        ];
      }
      {
        job_name = "cadvisor";
        static_configs = [ { targets = [ "localhost:${toString cadvisor.port}" ]; } ];
      }
    ];
  };

  systemd.services.claude-limits = {
    description = "Write Claude plan limits for node_exporter";
    serviceConfig = {
      Type = "oneshot";
      User = "aaron";
      StateDirectory = "claude-limits";
      ExecStart = lib.getExe claudeLimits;
    };
  };

  systemd.timers.claude-limits = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "1m";
      OnUnitActiveSec = "2m";
    };
  };

  services.grafana = {
    enable = true;
    declarativePlugins = with pkgs.grafanaPlugins; [
      yesoreyeram-infinity-datasource
      grafana-exploretraces-app
      grafana-lokiexplore-app
      grafana-metricsdrilldown-app
      grafana-pyroscope-app
    ];
    settings = {
      server = {
        http_addr = "127.0.0.1";
        http_port = 3001;
        domain = grafanaDomain;
        root_url = "https://${grafanaDomain}/";
      };
      security.secret_key = "$__file{${grafanaSecretKey}}";
    };

    provision.datasources.settings.deleteDatasources = [
      {
        name = "GitHub";
        orgId = 1;
      }
    ];
    provision.datasources.settings.datasources = [
      {
        name = "Prometheus";
        uid = prometheusUid;
        type = "prometheus";
        url = "http://localhost:${toString prometheus.port}";
        isDefault = true;
        jsonData.timeInterval = prometheus.globalConfig.scrape_interval;
      }
      {
        name = "Backlogic";
        uid = "backlogic";
        type = "yesoreyeram-infinity-datasource";
        url = backlogicUrl;
        jsonData = {
          auth_method = "bearerToken";
          allowedHosts = [ backlogicUrl ];
        };
        secureJsonData.bearerToken = "$__file{${grafanaBacklogicToken}}";
      }
    ];
  };

  services.grafana.provision.alerting = {
    contactPoints.settings.contactPoints = [
      {
        orgId = 1;
        name = discordContactPoint;
        receivers = [
          {
            uid = "discord";
            type = "discord";
            settings = {
              url = "$__file{${grafanaDiscordWebhook}}";
              use_discord_username = true;
            };
          }
        ];
      }
    ];

    policies.settings.policies = [
      {
        orgId = 1;
        receiver = discordContactPoint;
        group_by = [
          "grafana_folder"
          "alertname"
        ];
      }
    ];

    rules.settings.groups = [
      {
        orgId = 1;
        name = "spike";
        folder = "Alerts";
        interval = "1m";
        rules = [
          (alertRule {
            uid = "host-rebooted";
            title = "Host rebooted";
            summary = "{{ $$labels.host }} booted in the last ${
              toString (alertThresholds.recentBootSeconds / 60)
            } minutes.";
            expr = "time() - node_boot_time_seconds";
            evaluator = below alertThresholds.recentBootSeconds;
          })
          (alertRule {
            uid = "oom-kill";
            title = "OOM kill";
            summary = "The kernel killed a process on {{ $$labels.host }} for memory.";
            expr = "increase(node_vmstat_oom_kill[10m])";
            evaluator = above 0;
          })
          (alertRule {
            uid = "low-available-memory";
            title = "Low available memory";
            summary = "{{ $$labels.host }} has had under ${toString alertThresholds.minAvailableMebibytes} MiB available for 5 minutes.";
            expr = "node_memory_MemAvailable_bytes";
            evaluator = below (alertThresholds.minAvailableMebibytes * 1024 * 1024);
            for = "5m";
          })
          (alertRule {
            uid = "swap-full";
            title = "Swap nearly full";
            summary = "{{ $$labels.host }} has had over ${percent alertThresholds.maxSwapUsed} of its swap used for 5 minutes.";
            expr = "1 - node_memory_SwapFree_bytes / node_memory_SwapTotal_bytes";
            evaluator = above alertThresholds.maxSwapUsed;
            for = "5m";
          })
          (alertRule {
            uid = "root-inodes-full";
            title = "Root inodes nearly full";
            summary = "{{ $$labels.host }} has used over ${percent alertThresholds.maxRootInodesUsed} of the inodes on /.";
            expr = ''1 - node_filesystem_files_free{mountpoint="/"} / node_filesystem_files{mountpoint="/"}'';
            evaluator = above alertThresholds.maxRootInodesUsed;
          })
          (alertRule {
            uid = "service-restarting";
            title = "Service restarting";
            summary = "{{ $$labels.name }} on {{ $$labels.host }} restarted more than ${toString alertThresholds.maxServiceRestartsPerHour} times in the last hour.";
            expr = "increase(node_systemd_service_restart_total[1h])";
            evaluator = above alertThresholds.maxServiceRestartsPerHour;
          })
        ];
      }
    ];
  };

  services.caddy.virtualHosts.${grafanaDomain}.extraConfig = ''
    reverse_proxy ${grafana.settings.server.http_addr}:${toString grafana.settings.server.http_port}
  '';

  systemd.services.grafana.preStart = ''
    [ -f ${grafanaSecretKey} ] || (umask 077 && ${pkgs.openssl}/bin/openssl rand -hex 32 > ${grafanaSecretKey})
    [ -f ${grafanaBacklogicToken} ] || (umask 077 && touch ${grafanaBacklogicToken})
    [ -s ${grafanaDiscordWebhook} ] || (umask 077 && echo ${unsetDiscordWebhook} > ${grafanaDiscordWebhook})
  '';
}
