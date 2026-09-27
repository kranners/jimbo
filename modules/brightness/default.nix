{
  pkgs,
  lib,
  host,
  ...
}:
let
  inherit (lib) mkOption types;

  # jimbo drives a desktop monitor over DisplayPort, so there is no
  # /sys/class/backlight device and avizo's own lightctl cannot work.
  # Brightness has to travel over DDC/CI instead.
  brightness = pkgs.writeShellApplication {
    name = "brightness";

    runtimeInputs = [
      pkgs.avizo
      pkgs.ddcutil
      pkgs.gawk
      pkgs.util-linux
    ];

    text = ''
      step=5
      brightness_vcp_code=10

      exec 9>"''${XDG_RUNTIME_DIR:-/tmp}/brightness.lock"

      ddc() {
        ddcutil --noverify --sleep-multiplier 0.2 "$@"
      }

      read_percent() {
        ddc getvcp --brief "$brightness_vcp_code" | awk '{ print $4 }'
      }

      write_percent() {
        ddc setvcp "$brightness_vcp_code" "$1"
      }

      clamp() {
        if [ "$1" -lt 0 ]; then
          echo 0
        elif [ "$1" -gt 100 ]; then
          echo 100
        else
          echo "$1"
        fi
      }

      show_notification() {
        local resource

        if [ "$1" -gt 66 ]; then
          resource=brightness_high
        elif [ "$1" -gt 33 ]; then
          resource=brightness_medium
        else
          resource=brightness_low
        fi

        avizo-client \
          --image-resource="$resource" \
          --progress="$(awk -v percent="$1" 'BEGIN { print percent / 100 }')"
      }

      case "''${1:-get}" in
        get)
          flock 9
          read_percent
          ;;
        set)
          # Dragging a slider asks for far more writes than DDC/CI can carry,
          # so drop the requests that arrive while one is still in flight.
          flock --nonblock 9 || exit 0
          write_percent "$(clamp "$(printf '%.0f' "$2")")"
          ;;
        up | down)
          flock 9
          current=$(read_percent)

          if [ "$1" = up ]; then
            target=$(clamp "$((current + step))")
          else
            target=$(clamp "$((current - step))")
          fi

          write_percent "$target"
          show_notification "$target"
          ;;
        *)
          echo "usage: brightness [get | set PERCENT | up | down]" >&2
          exit 1
          ;;
      esac
    '';
  };
in
{
  options.brightness.command = mkOption {
    description = "Command that reads and changes the monitor brightness over DDC/CI.";
    type = types.str;
    default = "${brightness}/bin/brightness";
  };

  config = {
    nixosSystemModule = {
      hardware.i2c.enable = true;

      users.users.${host.username}.extraGroups = [ "i2c" ];
    };

    nixosHomeModule = {
      home.packages = [ brightness ];
    };
  };
}
