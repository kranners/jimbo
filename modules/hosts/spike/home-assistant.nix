{
  config,
  lib,
  pkgs,
  ...
}:
let
  lanInterfaces = [
    "wlp2s0"
    "wg0"
  ];

  # j-a-n/lovelace-wallpanel ships its built lovelace card as a release asset,
  # so this skips the build step nixpkgs' own custom-lovelace-modules packages have.
  wallpanelVersion = "4.67.2";
  wallpanel = pkgs.stdenvNoCC.mkDerivation {
    pname = "wallpanel";
    version = wallpanelVersion;

    src = pkgs.fetchurl {
      url = "https://github.com/j-a-n/lovelace-wallpanel/releases/download/v${wallpanelVersion}/wallpanel.js";
      hash = "sha256-RRKXw7DjIQkOKoGf17Abd19JAlzcXzoU8nQ2mOHff8k=";
    };

    dontUnpack = true;

    installPhase = ''
      mkdir -p $out
      cp $src $out/wallpanel.js
    '';

    meta = {
      description = "A screensaver and background image slideshow for Home Assistant's Lovelace UI";
      homepage = "https://github.com/j-a-n/lovelace-wallpanel";
      license = lib.licenses.gpl3Only;
    };
  };

  # Prometheus labels node_exporter's series by host once the framer kiosk issue lands;
  # until then the framer sensors below have no data, which is fine.
  statHosts = [
    "framer"
    "spike"
  ];

  statMetrics = [
    {
      key = "cpu_busy";
      name = "cpu busy";
      unit = "%";
      expr =
        host: ''100 - avg by (host) (rate(node_cpu_seconds_total{mode="idle",host="${host}"}[5m])) * 100'';
    }
    {
      key = "memory_used";
      name = "memory used";
      unit = "%";
      expr =
        host:
        ''(1 - node_memory_MemAvailable_bytes{host="${host}"} / node_memory_MemTotal_bytes{host="${host}"}) * 100'';
    }
    {
      key = "disk_used";
      name = "disk used";
      unit = "%";
      expr =
        host:
        ''(1 - node_filesystem_avail_bytes{mountpoint="/",host="${host}"} / node_filesystem_size_bytes{mountpoint="/",host="${host}"}) * 100'';
    }
    {
      key = "temperature";
      name = "temperature";
      unit = "°C";
      expr = host: ''max by (host) (node_hwmon_temp_celsius{host="${host}"})'';
    }
    {
      key = "load_per_core";
      name = "load per core";
      unit = "";
      expr =
        host:
        ''node_load5{host="${host}"} / count by (host) (node_cpu_seconds_total{mode="idle",host="${host}"})'';
    }
  ];

  hostQueries = lib.concatMap (
    host:
    map (metric: {
      name = "${host} ${metric.name}";
      unique_id = "${host}_${metric.key}";
      expr = metric.expr host;
      unit_of_measurement = metric.unit;
    }) statMetrics
  ) statHosts;

  batteryQuery = {
    name = "framer battery";
    unique_id = "framer_battery";
    expr = ''avg(node_power_supply_capacity{host="framer"})'';
    unit_of_measurement = "%";
  };

  statEntities = host: map (metric: "sensor.${host}_${metric.key}") statMetrics;

  infoCards = [
    {
      type = "clock";
    }
    {
      type = "weather-forecast";
      entity = "weather.home";
      forecast_type = "hourly";
    }
    {
      type = "weather-forecast";
      entity = "weather.home";
      forecast_type = "daily";
    }
    {
      type = "calendar";
      entities = [ "calendar.personal" ];
    }
    {
      type = "entities";
      title = "framer";
      entities = statEntities "framer" ++ [ "sensor.framer_battery" ];
    }
    {
      type = "entities";
      title = "spike";
      entities = statEntities "spike";
    }
  ];
in
{
  services.home-assistant = {
    enable = true;

    extraComponents = [
      "default_config"
      "open_meteo"
      "remote_calendar"
      "wyoming"
      "llama_cpp"
      "rest"
    ];

    customComponents = [ pkgs.home-assistant-custom-components.prometheus_sensor ];

    customLovelaceModules = with pkgs.home-assistant-custom-lovelace-modules; [
      kiosk-mode
      card-mod
      mushroom
      wallpanel
    ];

    config = {
      homeassistant = {
        name = "Home";
        unit_system = "metric";
        time_zone = config.time.timeZone;
        latitude = "!secret latitude";
        longitude = "!secret longitude";
        elevation = "!secret elevation";

        auth_providers = [
          { type = "homeassistant"; }
          {
            type = "trusted_networks";
            trusted_networks = [ "10.100.0.4/32" ];
            trusted_users."10.100.0.4" = [ "!secret panel_user_id" ];
            allow_bypass_login = true;
          }
        ];
      };

      sensor = [
        {
          platform = "prometheus_sensor";
          url = "http://localhost:9090";
          queries = hostQueries ++ [ batteryQuery ];
        }
      ];

      input_text.wallpanel_profile = {
        name = "Wallpanel profile";
        initial = "day";
      };

      automation = [
        {
          alias = "Wallpanel night profile";
          trigger = [
            {
              platform = "time";
              at = "20:00:00";
            }
          ];
          action = [
            {
              service = "input_text.set_value";
              target.entity_id = "input_text.wallpanel_profile";
              data.value = "night";
            }
          ];
        }
        {
          alias = "Wallpanel day profile";
          trigger = [
            {
              platform = "time";
              at = "06:30:00";
            }
          ];
          action = [
            {
              service = "input_text.set_value";
              target.entity_id = "input_text.wallpanel_profile";
              data.value = "day";
            }
          ];
        }
      ];
    };

    lovelaceConfig = {
      views = [
        {
          path = "panel";
          title = "Panel";
          cards = infoCards;
        }
      ];

      wallpanel = {
        enabled = true;
        hide_toolbar = true;
        hide_sidebar = true;
        idle_time = 15;
        display_time = 600;
        media_order = "random";
        image_animation_ken_burns = true;
        image_fit_landscape = "cover";
        image_url = "!secret unsplash_image_url";
        show_image_info = true;
        image_info_template = "Photo by \${user.name} on Unsplash";
        stop_screensaver_on_mouse_click = true;
        profile_entity = "input_text.wallpanel_profile";
        cards = infoCards;

        profiles = {
          day = { };
          night = {
            show_images = false;
            style.wallpanel-screensaver-overlay.background = "#000000ff";
            style.wallpanel-screensaver-info-box.opacity = "0.3";
          };
        };
      };
    };
  };

  networking.firewall.interfaces = lib.genAttrs lanInterfaces (_: {
    allowedTCPPorts = [ 8123 ];
  });
}
