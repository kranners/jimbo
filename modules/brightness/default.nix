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

      runtime_directory="''${XDG_RUNTIME_DIR:-/tmp}"
      bus_file="$runtime_directory/brightness.bus"
      target_file="$runtime_directory/brightness.target"

      exec 9>"$runtime_directory/brightness.lock"

      # Without an explicit bus, ddcutil probes every display on each call,
      # which costs more than the DDC/CI exchange itself.
      i2c_bus() {
        if [ ! -s "$bus_file" ]; then
          ddcutil detect --brief \
            | awk -F- '/I2C bus:/ { print $NF; exit }' > "$bus_file"
        fi

        cat "$bus_file"
      }

      ddc() {
        local bus
        bus=$(i2c_bus)

        if [ -n "$bus" ]; then
          ddcutil --noverify --bus "$bus" --sleep-multiplier 0.2 "$@"
        else
          ddcutil --noverify --sleep-multiplier 0.2 "$@"
        fi
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
          # Dragging a slider asks for far more writes than DDC/CI can carry.
          # Every request records where the slider is now, then one writer
          # chases that target and the rest exit, so the monitor always lands
          # on the position the finger stopped at instead of a stale one.
          clamp "$(printf '%.0f' "$2")" > "$target_file"

          flock --nonblock 9 || exit 0

          applied=
          while target=$(cat "$target_file") && [ "$target" != "$applied" ]; do
            write_percent "$target"
            applied=$target
          done
          ;;
        up | down)
          flock 9
          current=$(read_percent)

          if [ "$1" = up ]; then
            target=$(clamp "$((current + step))")
          else
            target=$(clamp "$((current - step))")
          fi

          echo "$target" > "$target_file"
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
