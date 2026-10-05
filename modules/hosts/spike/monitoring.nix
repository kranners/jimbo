{ config, pkgs, ... }:
let
  inherit (config.services) cadvisor grafana prometheus;
  grafanaSecretKey = "${grafana.dataDir}/secret_key";
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

    exporters.node = {
      enable = true;
      enabledCollectors = [ "systemd" ];
    };

    scrapeConfigs = [
      {
        job_name = "node";
        static_configs = [ { targets = [ "localhost:${toString prometheus.exporters.node.port}" ]; } ];
      }
      {
        job_name = "cadvisor";
        static_configs = [ { targets = [ "localhost:${toString cadvisor.port}" ]; } ];
      }
    ];
  };

  services.grafana = {
    enable = true;
    openFirewall = true;
    settings = {
      server.http_addr = "0.0.0.0";
      server.http_port = 3001;
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
    ];
  };

  systemd.services.grafana.preStart = ''
    [ -f ${grafanaSecretKey} ] || (umask 077 && ${pkgs.openssl}/bin/openssl rand -hex 32 > ${grafanaSecretKey})
  '';
}
