{ pkgs, ... }:
{
  nixosSystemModule.services.blueman.enable = true;

  nixosHomeModule.home.packages = [
    (pkgs.writeShellApplication {
      name = "quick-wifi";

      runtimeInputs = [
        pkgs.networkmanager
        pkgs.ghostty
        pkgs.jq
      ];

      text = ''
        wifi_device() {
          nmcli --terse --fields DEVICE,TYPE device \
            | awk --field-separator : '$2 == "wifi" { print $1; exit }'
        }

        saved_profiles() {
          nmcli --terse --escape no --fields NAME connection show
        }

        is_saved() {
          saved_profiles | grep --quiet --line-regexp --fixed-strings "$1"
        }

        case "''${1:-status}" in
          status)
            # SSIDs may contain colons, which nmcli escapes; take everything past
            # the last fixed-width field rather than splitting the whole line.
            active=$(
              nmcli --terse --escape no --fields TYPE,NAME connection show --active \
                | awk '/^802-11-wireless:/ { print substr($0, index($0, ":") + 1); exit }'
            )
            signal=$(
              nmcli --terse --fields IN-USE,SIGNAL device wifi list \
                | awk --field-separator : '$1 == "*" { print $2; exit }'
            )

            jq --null-input --compact-output \
              --arg enabled "$(nmcli --terse radio wifi)" \
              --arg ssid "$active" \
              --argjson signal "''${signal:-0}" \
              '{
                enabled: ($enabled == "enabled"),
                connected: ($ssid != ""),
                ssid: $ssid,
                signal: $signal,
                label: (if $ssid == "" then "Not connected" else $ssid end)
              }'
            ;;
          list)
            nmcli --terse --fields IN-USE,SIGNAL,SECURITY,SSID device wifi list \
              | jq --raw-input --slurp --compact-output --arg saved "$(saved_profiles)" '
                  ($saved | split("\n")) as $profiles
                  | [
                      split("\n")[]
                      | select(length > 0)
                      | capture("^(?<use>[^:]*):(?<signal>[^:]*):(?<security>[^:]*):(?<ssid>.*)$")
                      | .ssid |= gsub("\\\\:"; ":")
                      | select(.ssid != "")
                      | {
                          ssid: .ssid,
                          signal: (.signal | tonumber),
                          secure: (.security != ""),
                          active: (.use == "*"),
                          saved: (.ssid | IN($profiles[]))
                        }
                    ]
                  | group_by(.ssid)
                  | map(max_by(.signal) + { active: (map(.active) | any) })
                  | sort_by((.active | not), -.signal)
                '
            ;;
          toggle)
            if [ "$(nmcli --terse radio wifi)" = enabled ]; then
              nmcli radio wifi off
            else
              nmcli radio wifi on
            fi
            ;;
          rescan)
            nmcli device wifi rescan || true
            ;;
          connect)
            if is_saved "$2"; then
              nmcli connection up id "$2"
            else
              # Joining an unknown network needs a password prompt, which eww has
              # no business rendering. Hand the whole flow to nmtui.
              ghostty --class=quick-settings-tui -e nmtui-connect "$2" &
            fi
            ;;
          disconnect)
            nmcli device disconnect "$(wifi_device)"
            ;;
          *)
            echo "usage: quick-wifi [status|list|toggle|rescan|connect <ssid>|disconnect]" >&2
            exit 1
            ;;
        esac
      '';
    })

    (pkgs.writeShellApplication {
      name = "quick-bluetooth";

      runtimeInputs = [
        pkgs.bluez
        pkgs.blueman
        pkgs.jq
      ];

      text = ''
        powered() {
          bluetoothctl show \
            | awk '$1 == "Powered:" { print ($2 == "yes" ? "true" : "false"); exit }'
        }

        case "''${1:-status}" in
          status)
            jq --null-input --compact-output \
              --argjson powered "$(powered)" \
              '{
                powered: $powered,
                label: (if $powered then "Bluetooth on" else "Bluetooth off" end)
              }'
            ;;
          list)
            connected=$(bluetoothctl devices Connected 2>/dev/null | awk '{ print $2 }' || true)

            { bluetoothctl devices Paired 2>/dev/null || true; } \
              | jq --raw-input --slurp --compact-output --arg connected "$connected" '
                  ($connected | split("\n")) as $active
                  | [
                      split("\n")[]
                      | capture("^Device (?<mac>\\S+) (?<name>.*)$")
                      | { mac, name, connected: (.mac | IN($active[])) }
                    ]
                  | sort_by((.connected | not), .name)
                '
            ;;
          toggle)
            if [ "$(powered)" = true ]; then
              bluetoothctl power off
            else
              bluetoothctl power on
            fi
            ;;
          connect)
            bluetoothctl connect "$2"
            ;;
          disconnect)
            bluetoothctl disconnect "$2"
            ;;
          pair)
            # Pairing needs agent interaction and a PIN; blueman already does it well.
            blueman-manager &
            ;;
          *)
            echo "usage: quick-bluetooth [status|list|toggle|connect <mac>|disconnect <mac>|pair]" >&2
            exit 1
            ;;
        esac
      '';
    })

    (pkgs.writeShellApplication {
      name = "quick-processes";

      runtimeInputs = [
        pkgs.procps
        pkgs.jq
      ];

      text = ''
        case "''${1:-list}" in
          list)
            # eww polls a static command, so both orderings go out together and
            # the dashboard's sort toggle just picks one.
            ps -eo pid,pcpu,pmem,comm:32 --no-headers \
              | jq --raw-input --slurp --compact-output '
                  [
                    split("\n")[]
                    | select(length > 0)
                    | capture("^\\s*(?<pid>\\d+)\\s+(?<cpu>\\S+)\\s+(?<mem>\\S+)\\s+(?<name>.*?)\\s*$")
                    | {
                        pid: (.pid | tonumber),
                        cpu: (.cpu | tonumber),
                        mem: (.mem | tonumber),
                        # Nix wrapper scripts all present as .foo-wrapped.
                        name: (.name | sub("^\\."; "") | sub("-wrapped$"; ""))
                      }
                  ]
                  | {
                      cpu: (sort_by(-.cpu) | .[:10]),
                      mem: (sort_by(-.mem) | .[:10])
                    }
                '
            ;;
          kill)
            kill "$2"
            ;;
          force-kill)
            kill -KILL "$2"
            ;;
          *)
            echo "usage: quick-processes [list|kill <pid>|force-kill <pid>]" >&2
            exit 1
            ;;
        esac
      '';
    })
  ];
}
