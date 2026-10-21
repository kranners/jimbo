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

  framerSatellite = "assist_satellite.framer";
  framerVoice = "sensor.framer_voice";
  framerConversation = "binary_sensor.framer_conversation";
  framerMute = "switch.framer_mute";
  framerScreen = "light.framer_screen";
  framerScreenBrightness = "sensor.framer_screen_brightness";
  framerScreenAndMicrophoneOff = "switch.framer_screen_and_microphone_off";
  framerPanelRemote = "http://10.100.0.5:8124";
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
          inset: 0;
          height: auto;
          z-index: 10;
          display: flex;
          flex-direction: column;
          justify-content: flex-end;
          padding: 0 6vw 12vh;
          box-sizing: border-box;
          pointer-events: none;
          background: linear-gradient(to top, rgba(0, 0, 0, 0.9), rgba(0, 0, 0, 0.6) 40%, transparent 75%);
          border: none;
          border-radius: 0;
          box-shadow: none;
          text-align: center;
          font-size: 3.5em;
          line-height: 1.3;
          text-shadow: 0 0.05em 0.2em black;
          --primary-text-color: white;
          --secondary-text-color: rgba(255, 255, 255, 0.75);
          --mdc-icon-size: 1em;
          {% if is_state('${framerSatellite}', 'listening') %}
          animation: listening 1.2s ease-in-out infinite;
          {% endif %}
        }
        @keyframes listening {
          50% { background: linear-gradient(to top, var(--primary-color), rgba(0, 0, 0, 0.6) 40%, transparent 75%); }
        }
      '';
    };
  };

  muteCard = {
    type = "tile";
    entity = framerMute;
    name = "Mute microphone";
  };

  refreshFramerScreenBrightness = {
    action = "homeassistant.update_entity";
    target.entity_id = framerScreenBrightness;
  };

  runFramerPanel = command: [
    {
      action = "rest_command.framer_panel";
      data.command = command;
    }
    refreshFramerScreenBrightness
  ];

  framerControlCards = [
    {
      type = "tile";
      entity = framerScreenAndMicrophoneOff;
      name = "Screen and microphone off";
    }
    {
      type = "tile";
      entity = framerScreen;
      name = "Screen";
      features = [ { type = "light-brightness"; } ];
    }
    muteCard
  ];

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
          light = [
            {
              name = "framer screen";
              unique_id = "framer_screen";
              availability = "{{ has_value('${framerScreenBrightness}') }}";
              state = "{{ states('${framerScreenBrightness}') | int(0) > 0 }}";
              level = "{{ (states('${framerScreenBrightness}') | int(0) * 2.55) | round(0) | int }}";
              turn_on = runFramerPanel "on";
              turn_off = runFramerPanel "off";
              set_level = runFramerPanel "brightness/{{ [1, (brightness / 2.55) | round(0) | int] | max }}";
            }
          ];
          switch = [
            {
              name = "framer screen and microphone off";
              unique_id = "framer_screen_and_microphone_off";
              state = "{{ is_state('${framerScreen}', 'off') and is_state('${framerMute}', 'on') }}";
              turn_on = [
                {
                  action = "light.turn_off";
                  target.entity_id = framerScreen;
                }
                {
                  action = "switch.turn_on";
                  target.entity_id = framerMute;
                }
              ];
              turn_off = [
                {
                  action = "light.turn_on";
                  target.entity_id = framerScreen;
                }
                {
                  action = "switch.turn_off";
                  target.entity_id = framerMute;
                }
              ];
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

      rest = [
        {
          resource = "${framerPanelRemote}/brightness";
          scan_interval = 30;
          sensor = [
            {
              name = "framer screen brightness";
              unique_id = "framer_screen_brightness";
              unit_of_measurement = "%";
            }
          ];
        }
      ];

      rest_command.framer_panel = {
        url = "${framerPanelRemote}/{{ command }}";
        method = "post";
      };

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
          alias = "Reconnect framer's satellite when it is stuck listening";
          trigger = [
            {
              platform = "state";
              entity_id = framerSatellite;
              to = "listening";
              for.seconds = 30;
            }
          ];
          action = [
            {
              service = "homeassistant.reload_config_entry";
              target.entity_id = framerSatellite;
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
          cards = [ voiceCard ] ++ infoCards ++ [ muteCard ];
        }
        {
          path = "framer";
          title = "Framer";
          cards = framerControlCards;
        }
      ];

      wallpanel = {
        enabled = true;
        enabled_on_views = [ "panel" ];
        hide_toolbar = true;
        hide_sidebar = true;
        idle_time = 15;
        display_time = 600;
        media_order = "random";
        image_animation_ken_burns = true;
        image_fit_portrait = "cover";
        image_url = "/wallpapers";
        stop_screensaver_on_mouse_click = true;
        alert_errors = false;
        profile_entity = "sensor.panel_profile";
        screensaver_entity = panelScreensaver;
        cards = infoCards;
        style.wallpanel-screensaver-info-box-content = {
          zoom = "2";
          "--wp-card-width" = "460px";
        };

        profiles = {
          voice.idle_time = 0;
          day.style.wallpanel-screensaver-info-box.opacity = "1";
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
