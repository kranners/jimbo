{
  lib,
  config,
  ...
}:
let
  inherit (lib) mkOption types;

  temperature = types.ints.between 1000 20000;
in
{
  options.nightShift = {
    temperature = mkOption {
      description = "Colour temperature in K night shift starts at, before the slider moves it.";
      type = temperature;
      default = 4000;
    };

    minTemperature = mkOption {
      description = "Warmest colour temperature in K the slider reaches.";
      type = temperature;
      default = 2000;
    };

    daylightTemperature = mkOption {
      description = "Colour temperature in K applied while night shift is off, hyprsunset's default.";
      type = temperature;
      default = 6000;
    };
  };

  config.nixosHomeModule =
    { pkgs, ... }:
    {
      services.hyprsunset.enable = true;

      home.packages = [
        (pkgs.writeShellApplication {
          name = "night-shift";

          runtimeInputs = [
            pkgs.hyprland
            pkgs.jq
          ];

          text = ''
            minimum=${toString config.nightShift.minTemperature}
            daylight=${toString config.nightShift.daylightTemperature}

            state_directory="''${XDG_STATE_HOME:-$HOME/.local/state}/night-shift"
            setpoint_file="$state_directory/temperature"

            read_temperature() {
              case "$1" in
                "" | *[!0-9]*) echo "$2" ;;
                *) echo "$1" ;;
              esac
            }

            clamp() {
              awk -v value="$1" -v minimum="$minimum" -v maximum="$daylight" 'BEGIN {
                value = int(value + 0.5)
                if (value < minimum) value = minimum
                if (value > maximum) value = maximum
                print value
              }'
            }

            apply() {
              hyprctl hyprsunset temperature "$1" > /dev/null
            }

            setpoint=$(
              read_temperature \
                "$(cat "$setpoint_file" 2>/dev/null || true)" \
                ${toString config.nightShift.temperature}
            )

            current=$(
              read_temperature \
                "$(hyprctl hyprsunset temperature 2>/dev/null || true)" \
                "$daylight"
            )

            if [ "$current" -lt "$daylight" ]; then
              active=true
            else
              active=false
            fi

            save_setpoint() {
              mkdir -p "$state_directory"
              echo "$1" > "$setpoint_file"
            }

            case "''${1:-status}" in
              on)
                apply "$setpoint"
                ;;
              off)
                apply "$daylight"
                ;;
              toggle)
                if [ "$active" = true ]; then
                  apply "$daylight"
                else
                  apply "$setpoint"
                fi
                ;;
              set)
                setpoint=$(clamp "$2")
                save_setpoint "$setpoint"
                apply "$setpoint"
                ;;
              step)
                setpoint=$(clamp "$(awk -v from="$setpoint" -v by="$2" 'BEGIN { print from + by }')")
                save_setpoint "$setpoint"
                apply "$setpoint"
                ;;
              status)
                jq --null-input --compact-output \
                  --argjson active "$active" \
                  --argjson temperature "$current" \
                  --argjson setpoint "$setpoint" \
                  --argjson minimum "$minimum" \
                  --argjson daylight "$daylight" \
                  '{
                    active: $active,
                    temperature: $temperature,
                    setpoint: $setpoint,
                    minimum: $minimum,
                    maximum: $daylight,
                    text: "\(if $active then "󰖔" else "󰖨" end) \($temperature)K",
                    class: (if $active then "active" else "inactive" end),
                    label: (if $active
                            then "Night shift \($temperature)K"
                            else "Night shift off"
                            end)
                  } | .tooltip = "\(.label), slider \($setpoint)K"'
                ;;
              *)
                echo "usage: night-shift [on|off|toggle|set <K>|step <delta>|status]" >&2
                exit 1
                ;;
            esac
          '';
        })
      ];
    };
}
