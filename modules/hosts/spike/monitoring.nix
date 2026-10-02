{ config, pkgs, ... }:
let
  inherit (config.services) cadvisor grafana prometheus;
  grafanaSecretKey = "${grafana.dataDir}/secret_key";
in
{
  services.cadvisor.enable = true;

  services.prometheus = {
    enable = true;
    exporters.node.enable = true;

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
      security.secret_key = "$__file{${grafanaSecretKey}}";
    };

    provision.datasources.settings.datasources = [
      {
        name = "Prometheus";
        type = "prometheus";
        url = "http://localhost:${toString prometheus.port}";
        isDefault = true;
      }
    ];
  };

  systemd.services.grafana.preStart = ''
    [ -f ${grafanaSecretKey} ] || (umask 077 && ${pkgs.openssl}/bin/openssl rand -hex 32 > ${grafanaSecretKey})
  '';
}
