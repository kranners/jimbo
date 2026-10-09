{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.services) cadvisor grafana prometheus;
  grafanaSecretKey = "${grafana.dataDir}/secret_key";
  grafanaGithubToken = "${grafana.dataDir}/github-token";
  grafanaDomain = "grafana.spike.cute.engineer";
  textfileDir = "/var/lib/claude-limits";

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
      extraFlags = [ "--collector.textfile.directory=${textfileDir}" ];
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
      grafana-github-datasource
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

    provision.datasources.settings.datasources = [
      {
        name = "Prometheus";
        type = "prometheus";
        url = "http://localhost:${toString prometheus.port}";
        isDefault = true;
        jsonData.timeInterval = prometheus.globalConfig.scrape_interval;
      }
      {
        name = "GitHub";
        uid = "github";
        type = "grafana-github-datasource";
        jsonData = {
          selectedAuthType = "personal-access-token";
          cachingEnabled = true;
        };
        secureJsonData.accessToken = "$__file{${grafanaGithubToken}}";
      }
    ];
  };

  services.caddy.virtualHosts.${grafanaDomain}.extraConfig = ''
    reverse_proxy ${grafana.settings.server.http_addr}:${toString grafana.settings.server.http_port}
  '';

  systemd.services.grafana.preStart = ''
    [ -f ${grafanaSecretKey} ] || (umask 077 && ${pkgs.openssl}/bin/openssl rand -hex 32 > ${grafanaSecretKey})
    [ -f ${grafanaGithubToken} ] || (umask 077 && touch ${grafanaGithubToken})
  '';
}
