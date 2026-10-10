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

  framerAddress = "192.168.4.25";

  wallpaperDirectory = "${config.services.home-assistant.configDir}/media/wallpapers";
  keptWallpapers = 60;

  wallpaperSearchParameters = [
    "sorting=random"
    "atleast=1440x2560"
    "ratios=portrait"
    "categories=100"
    "purity=100"
  ];

  wallpaperQueries = [
    "nature -women -men -people"
    "aerial view -women -men -people"
  ];

  fetch-panel-wallpapers = pkgs.writeShellApplication {
    name = "fetch-panel-wallpapers";

    runtimeInputs = [
      pkgs.curl
      pkgs.jq
      pkgs.coreutils
      pkgs.findutils
    ];

    text = ''
      mkdir -p "${wallpaperDirectory}"

      for query in ${lib.escapeShellArgs wallpaperQueries}; do
        curl -fsSG --data-urlencode "q=$query" "https://wallhaven.cc/api/v1/search?${builtins.concatStringsSep "&" wallpaperSearchParameters}" \
          | jq -r '.data[].path' \
          | while read -r url; do
              destination="${wallpaperDirectory}/$(basename "$url")"
              [ -e "$destination" ] || curl -fsS -o "$destination" "$url"
            done
      done

      find "${wallpaperDirectory}" -maxdepth 1 -type f -printf '%T@ %p\0' \
        | sort -zrn \
        | tail -zn "+$((${toString keptWallpapers} + 1))" \
        | cut -zd' ' -f2- \
        | xargs -0r rm --
    '';
  };

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

  spokenConditions = {
    clear-night = "clear";
    partlycloudy = "partly cloudy";
    lightning-rainy = "storms";
    snowy-rainy = "sleet";
    windy-variant = "windy";
  };

  dailyForecastIntent = dayName: forecastIndex: {
    action = [
      {
        action = "weather.get_forecasts";
        target.entity_id = "weather.home";
        data.type = "daily";
        response_variable = "forecasts";
      }
      {
        stop = "";
        response_variable = "forecasts";
      }
    ];
    speech.text = ''
      {% set day = action_response['weather.home'].forecast[${toString forecastIndex}] %}
      {% set spoken = ${builtins.toJSON spokenConditions} %}
      ${dayName}, {{ spoken.get(day.condition, day.condition) }}, a high of {{ day.temperature | round }} and a low of {{ day.templow | round }} degrees
      {%- if day.precipitation %}, with {{ day.precipitation }} millimetres of rain{% endif %}.
    '';
  };

  hardwareMetrics = [
    {
      key = "cpu_busy";
      name = "cpu busy";
      unit = "%";
      expr = ''round(100 - avg(rate(node_cpu_seconds_total{mode="idle",host="spike"}[5m])) * 100, 0.1)'';
    }
    {
      key = "memory_used";
      name = "memory used";
      unit = "%";
      expr = ''round((1 - node_memory_MemAvailable_bytes{host="spike"} / node_memory_MemTotal_bytes{host="spike"}) * 100, 0.1)'';
    }
    {
      key = "disk_used";
      name = "disk used";
      unit = "%";
      expr = ''round((1 - node_filesystem_avail_bytes{mountpoint="/",host="spike"} / node_filesystem_size_bytes{mountpoint="/",host="spike"}) * 100, 0.1)'';
    }
    {
      key = "temperature";
      name = "temperature";
      unit = "°C";
      expr = ''round(max(node_hwmon_temp_celsius{host="spike"}), 0.1)'';
    }
    {
      key = "load_per_core";
      name = "load per core";
      unit = "";
      expr = ''round(node_load5{host="spike"} / on (host) count by (host) (node_cpu_seconds_total{mode="idle",host="spike"}), 0.01)'';
    }
  ];

  claudeLimitMetrics = [
    {
      key = "claude_session_limit";
      name = "claude session limit";
      unit = "%";
      expr = ''max(claude_limit_percent{kind="session"})'';
    }
    {
      key = "claude_weekly_limit";
      name = "claude weekly limit";
      unit = "%";
      expr = ''max(claude_limit_percent{kind="weekly_all"})'';
    }
    {
      key = "claude_weekly_scoped_limit";
      name = "claude weekly scoped limit";
      unit = "%";
      expr = ''max(claude_limit_percent{kind="weekly_scoped"})'';
    }
  ];

  claudeActivityMetrics = [
    {
      key = "claude_live_sessions";
      name = "claude live sessions";
      unit = "";
      expr = "count(count by (job, session_id) (claude_code_session_count_total)) or vector(0)";
    }
    {
      key = "busy_workaholic_runners";
      name = "busy workaholic runners";
      unit = "";
      expr = ''count(node_systemd_unit_state{name=~"workaholic@.+",state="activating"} == 1) or vector(0)'';
    }
  ];

  statQueries = map (metric: {
    name = "spike ${metric.name}";
    unique_id = "spike_${metric.key}";
    inherit (metric) expr;
    unit_of_measurement = metric.unit;
  }) (hardwareMetrics ++ claudeLimitMetrics ++ claudeActivityMetrics);

  historyGraph = title: metrics: {
    type = "history-graph";
    inherit title;
    hours_to_show = 24;
    entities = map (metric: "sensor.spike_${metric.key}") metrics;
  };

  framerSatellite = "assist_satellite.framer";
  framerVoice = "sensor.framer_voice";
  framerConversation = "binary_sensor.framer_conversation";
  panelScreensaver = "input_boolean.panel_screensaver";
  wallpanelProfile = "input_text.wallpanel_profile";
  secondsToReadReply = 30;

  voiceCard = {
    type = "conditional";
    conditions = [
      {
        condition = "state";
        entity = framerConversation;
        state = "on";
      }
    ];
    card = {
      type = "markdown";
      content = ''
        {% set satellite = states('${framerSatellite}') %}
        {% set heard = state_attr('${framerVoice}', 'heard') or "" %}
        {% set reply = state_attr('${framerVoice}', 'reply') or "" %}
        {% if satellite == 'listening' %}
        # <ha-icon icon="mdi:microphone"></ha-icon> Listening…
        {% elif satellite == 'processing' %}
        # <ha-icon icon="mdi:dots-horizontal"></ha-icon> Thinking…
        {% else %}
        # <ha-icon icon="mdi:account-voice"></ha-icon>
        {% endif %}
        {% if heard %}
        > {{ heard }}
        {% endif %}

        {{ reply }}
      '';
      card_mod.style = ''
        ha-card {
          position: fixed;
          left: 50%;
          bottom: 8vh;
          transform: translateX(-50%);
          width: min(80vw, 900px);
          height: auto;
          z-index: 10;
          font-size: 1.5em;
          {% if is_state('${framerSatellite}', 'listening') %}
          animation: listening 1.2s ease-in-out infinite;
          {% endif %}
        }
        @keyframes listening {
          50% { box-shadow: 0 0 0 1.5vh var(--primary-color); }
        }
      '';
    };
  };

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
    (historyGraph "spike" hardwareMetrics)
    (historyGraph "plan limits used" claudeLimitMetrics)
    (historyGraph "claude" claudeActivityMetrics)
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
      "apple_tv"
      "thread"
      "google_translate"
      "google"
      "google_tasks"
    ];

    customComponents = [ pkgs.home-assistant-custom-components.prometheus_sensor ];

    customLovelaceModules = with pkgs.home-assistant-custom-lovelace-modules; [
      kiosk-mode
      card-mod
      mushroom
      wallpanel
    ];

    config = {
      default_config = { };

      homeassistant = {
        name = "Home";
        unit_system = "metric";
        time_zone = config.time.timeZone;
        latitude = "!secret latitude";
        longitude = "!secret longitude";
        elevation = "!secret elevation";
        media_dirs.wallpapers = wallpaperDirectory;

        auth_providers = [
          { type = "homeassistant"; }
          {
            type = "trusted_networks";
            trusted_networks = [ "${framerAddress}/32" ];
            trusted_users.${framerAddress} = [ "!secret panel_user_id" ];
            allow_bypass_login = true;
          }
        ];
      };

      sensor = [
        {
          platform = "prometheus_sensor";
          url = "http://localhost:9090";
          queries = statQueries;
        }
      ];

      template = [
        {
          trigger = [
            {
              platform = "webhook";
              webhook_id = "framer-voice";
              allowed_methods = [ "POST" ];
              local_only = true;
            }
          ];
          sensor = [
            {
              name = "framer voice";
              unique_id = "framer_voice";
              device_class = "timestamp";
              state = "{{ now().isoformat() }}";
              attributes = {
                heard = "{{ trigger.json.heard if 'heard' in trigger.json else this.attributes.get('heard', '') }}";
                reply = "{{ trigger.json.reply if 'reply' in trigger.json else this.attributes.get('reply', '') }}";
              };
            }
          ];
        }
        {
          binary_sensor = [
            {
              name = "framer conversation";
              unique_id = "framer_conversation";
              state = "{{ states('${framerSatellite}') in ['listening', 'processing', 'responding'] }}";
              delay_off.seconds = secondsToReadReply;
            }
          ];
          sensor = [
            {
              name = "panel profile";
              unique_id = "panel_profile";
              state = "{{ 'voice' if is_state('${framerConversation}', 'on') else states('${wallpanelProfile}') }}";
            }
          ];
        }
      ];

      input_boolean.panel_screensaver.name = "Panel screensaver";
      conversation.intents = {
        WeatherForecastToday = [
          "(what is|what's) the forecast [for today]"
          "(what is|what's) the weather [going to be] [like] today"
          "(what is|what's) today's (weather|forecast)"
          "(will|is) it [going to] rain today"
        ];
        WeatherForecastTomorrow = [
          "(what is|what's) the forecast for tomorrow"
          "(what is|what's) the weather [going to be] [like] tomorrow"
          "(what is|what's) tomorrow's (weather|forecast)"
          "(will|is) it [going to] rain tomorrow"
        ];
      };

      intent_script = {
        WeatherForecastToday = dailyForecastIntent "Today" 0;
        WeatherForecastTomorrow = dailyForecastIntent "Tomorrow" 1;
      };

      input_text.wallpanel_profile = {
        name = "Wallpanel profile";
        initial = "day";
      };

      automation = [
        {
          alias = "Wake the panel while framer is in a conversation";
          trigger = [
            {
              platform = "state";
              entity_id = framerConversation;
              to = "on";
            }
          ];
          action = [
            {
              service = "input_boolean.turn_off";
              target.entity_id = panelScreensaver;
            }
          ];
        }
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
              target.entity_id = wallpanelProfile;
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
              target.entity_id = wallpanelProfile;
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
          cards = [ voiceCard ] ++ infoCards;
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
        image_fit_portrait = "cover";
        image_url = "/wallpapers";
        stop_screensaver_on_mouse_click = true;
        profile_entity = "sensor.panel_profile";
        screensaver_entity = panelScreensaver;
        cards = infoCards;

        profiles = {
          voice.idle_time = 0;
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

  # Framer's kiosk polls this file, needing no login, and reloads when it changes,
  # because WallPanel builds its screensaver once per page load.
  systemd.tmpfiles.settings.panel-version = {
    "${config.services.home-assistant.configDir}/www".d = {
      user = "hass";
      group = "hass";
      mode = "0755";
    };
    "${config.services.home-assistant.configDir}/www/panel-version"."f+" = {
      user = "hass";
      group = "hass";
      mode = "0644";
      argument = builtins.hashString "sha256" (
        builtins.toJSON {
          inherit (config.services.home-assistant) lovelaceConfig;
          frontend = config.services.home-assistant.package.version;
          modules = map (module: module.name) config.services.home-assistant.customLovelaceModules;
        }
      );
    };
  };

  systemd.services.panel-wallpapers = {
    description = "wallhaven wallpaper fetcher for the Home Assistant panel";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];

    serviceConfig = {
      Type = "oneshot";
      User = "hass";
      ExecStart = lib.getExe fetch-panel-wallpapers;
    };
  };

  systemd.timers.panel-wallpapers = {
    wantedBy = [ "timers.target" ];

    timerConfig = {
      OnBootSec = "2m";
      OnUnitActiveSec = "1d";
      Persistent = true;
    };
  };

  networking.firewall.interfaces = lib.genAttrs lanInterfaces (_: {
    allowedTCPPorts = [ 8123 ];
  });
}
