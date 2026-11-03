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

  butler-card = pkgs.stdenvNoCC.mkDerivation {
    pname = "butler-card";
    version = builtins.substring 0 12 (builtins.hashFile "sha256" ./butler-card/butler-card.js);

    src = ./butler-card/butler-card.js;

    dontUnpack = true;

    installPhase = ''
      mkdir -p $out
      cp $src $out/butler-card.js
    '';

    passthru.entrypoint = "butler-card.js";
  };

  movie-night-card =
    let
      source =
        builtins.replaceStrings
          [ "@BUTLER_SVG@" ]
          [ (builtins.readFile ./butler-card/butler-greyscale.svg) ]
          (builtins.readFile ./butler-card/movie-night-card.js);
    in
    pkgs.stdenvNoCC.mkDerivation {
      pname = "framer-movie-night-card";
      version = builtins.substring 0 12 (builtins.hashString "sha256" source);

      src = pkgs.writeText "movie-night-card.js" source;

      dontUnpack = true;

      installPhase = ''
        mkdir -p $out
        cp $src $out/movie-night-card.js
      '';

      passthru.entrypoint = "movie-night-card.js";
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
  # Dim but visible, so the off screen's time and weather still show.
  framerScreenOffPercent = 5;
  panelScreensaver = "input_boolean.panel_screensaver";
  wallpanelProfile = "input_text.wallpanel_profile";
  framerMovieNight = "input_boolean.framer_movie_night";
  secondsToReadReply = 30;
  conversationStates = [
    "listening"
    "processing"
    "responding"
  ];

  voiceCard = {
    type = "custom:butler-voice-card";
    conversation = framerConversation;
    satellite = framerSatellite;
    voice = framerVoice;
  };

  # The dark card: a dim greyscale Butler, the time and the weather's icon, temperature and condition.
  darkCard = {
    type = "custom:framer-movie-night-card";
  };

  movieNightCard = {
    type = "tile";
    entity = framerMovieNight;
    name = "Movie night (panel off)";
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
    movieNightCard
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
      butler-card
      movie-night-card
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
        radius = 75;
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
              state = "{{ states('${framerScreenBrightness}') | int(100) <= ${toString framerScreenOffPercent} and is_state('${framerMute}', 'on') }}";
              turn_on = [
                {
                  action = "switch.turn_on";
                  target.entity_id = framerMute;
                }
              ]
              ++ runFramerPanel "brightness/${toString framerScreenOffPercent}";
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
          trigger = [
            {
              platform = "state";
              entity_id = framerSatellite;
              to = conversationStates;
              id = "active";
            }
            {
              platform = "state";
              entity_id = framerSatellite;
              not_to = conversationStates;
              for.seconds = secondsToReadReply;
              id = "read";
            }
            {
              platform = "event";
              event_type = "framer_dismissed";
              id = "dismissed";
            }
            {
              platform = "homeassistant";
              event = "start";
              id = "started";
            }
          ];
          # A dismissed conversation stays hidden while Home Assistant finishes
          # it, until the next wake starts listening.
          binary_sensor = [
            {
              name = "framer conversation";
              unique_id = "framer_conversation";
              state = "{{ trigger.id == 'active' and (trigger.to_state.state == 'listening' or this.state == 'on') }}";
            }
          ];
        }
        {
          sensor = [
            {
              name = "panel profile";
              unique_id = "panel_profile";
              state = "{{ 'voice' if is_state('${framerConversation}', 'on') and is_state('${framerMute}', 'off') else 'movie' if is_state('${framerMovieNight}', 'on') else 'off' if is_state('${framerMute}', 'on') else states('${wallpanelProfile}') }}";
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
      # Restored across restarts, so a flip by hand holds until the next window.
      input_boolean.framer_movie_night = {
        name = "Framer movie night";
        icon = "mdi:movie-open";
      };
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
          alias = "Dismiss framer's conversation";
          trigger = [
            {
              platform = "webhook";
              webhook_id = "framer-dismiss";
              allowed_methods = [ "POST" ];
              local_only = true;
            }
          ];
          action = [
            { event = "framer_dismissed"; }
            {
              # Reconnecting the satellite is the only way to cancel its pipeline.
              condition = "template";
              value_template = "{{ states('${framerSatellite}') in ${builtins.toJSON conversationStates} }}";
            }
            {
              service = "homeassistant.reload_config_entry";
              target.entity_id = framerSatellite;
            }
          ];
        }
        {
          alias = "Toggle framer's assistant";
          trigger = [
            {
              platform = "webhook";
              webhook_id = "framer-assistant-toggle";
              allowed_methods = [ "POST" ];
              local_only = true;
            }
          ];
          action = [
            {
              service = "switch.toggle";
              target.entity_id = framerMute;
            }
          ];
        }
        {
          alias = "Show only the time and weather while framer's assistant is off";
          trigger = [
            {
              platform = "state";
              entity_id = framerMute;
              to = "on";
            }
          ];
          action = [
            {
              service = "input_boolean.turn_on";
              target.entity_id = panelScreensaver;
            }
          ];
        }
        {
          alias = "Start framer's movie night";
          trigger = [
            {
              platform = "time";
              at = "19:30:00";
            }
          ];
          condition = [
            {
              condition = "time";
              weekday = [ "wed" ];
            }
          ];
          action = [
            {
              service = "input_boolean.turn_on";
              target.entity_id = framerMovieNight;
            }
          ];
        }
        {
          alias = "End framer's movie night";
          trigger = [
            {
              platform = "time";
              at = "23:00:00";
            }
          ];
          condition = [
            {
              condition = "time";
              weekday = [ "wed" ];
            }
          ];
          action = [
            {
              service = "input_boolean.turn_off";
              target.entity_id = framerMovieNight;
            }
          ];
        }
        {
          alias = "Turn framer's screen and assistant down for movie night";
          trigger = [
            {
              platform = "state";
              entity_id = framerMovieNight;
              from = "off";
              to = "on";
            }
          ];
          action = [
            {
              service = "switch.turn_on";
              target.entity_id = framerMute;
            }
            {
              service = "input_boolean.turn_on";
              target.entity_id = panelScreensaver;
            }
          ]
          ++ runFramerPanel "brightness/15";
        }
        {
          alias = "Bring framer's screen and assistant back after movie night";
          trigger = [
            {
              platform = "state";
              entity_id = framerMovieNight;
              from = "on";
              to = "off";
            }
          ];
          action = [
            {
              service = "switch.turn_off";
              target.entity_id = framerMute;
            }
          ]
          ++ runFramerPanel "schedule";
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
          cards = [
            voiceCard
          ]
          ++ infoCards
          ++ [
            muteCard
            movieNightCard
          ];
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
          movie = {
            idle_time = 10;
            show_images = false;
            cards = [ darkCard ];
            style.wallpanel-screensaver-overlay.background = "#000000ff";
            style.wallpanel-screensaver-info-box.opacity = "1";
          };
          off = {
            idle_time = 10;
            show_images = false;
            cards = [ darkCard ];
            style.wallpanel-screensaver-overlay.background = "#000000ff";
            style.wallpanel-screensaver-info-box.opacity = "1";
          };
          day = {
            cards = infoCards;
            style.wallpanel-screensaver-info-box.opacity = "1";
          };
          night = {
            show_images = false;
            cards = [ darkCard ];
            style.wallpanel-screensaver-overlay.background = "#000000ff";
            style.wallpanel-screensaver-info-box.opacity = "1";
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
