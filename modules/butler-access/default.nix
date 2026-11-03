{ host, lib, ... }:
let
  butlerKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICGnAjeBfFUnArQrUvixG5Sq07j/JdkwyyS2P8jYl7sj butler@spike-macs";
  spike = "10.100.0.1";
  home = "/Users/${host.username}";
  passwordFile = "${home}/.local/state/butler-access/vnc-password";
  remoteManagement = "/Library/Preferences/com.apple.RemoteManagement";
  kickstart = "/System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart";
  anchor = "com.apple/butler-access";
  rules = "/etc/pf.anchors/butler-access";
  loadRules = "/sbin/pfctl -q -a ${anchor} -f ${rules} 2> /dev/null && /sbin/pfctl -q -E 2> /dev/null";
  # pilot is the employer's Jamf-managed Mac, whose lock policy keep-awake would sidestep, so it stays off there until
  # Aaron turns it on himself.
  keepAwakeByDefault = host.hostname != "pilot";
in
{
  darwinHomeModule =
    { pkgs, ... }:
    let
      keepawake = pkgs.writeShellScriptBin "butler-keepawake" ''
        set -u
        file="$HOME/.local/state/butler-access/keepawake"
        label=butler-keepawake
        default=${if keepAwakeByDefault then "on" else "off"}

        wanted() {
          case "$(cat "$file" 2> /dev/null)" in
            on) echo on ;;
            off) echo off ;;
            *) echo "$default" ;;
          esac
        }

        restart() {
          /bin/launchctl kickstart -k "gui/$(id -u)/$label" > /dev/null 2>&1 \
            || echo "could not restart $label; it takes the change within 30 s"
        }

        set_to() {
          /bin/mkdir -p "$(dirname "$file")"
          printf '%s\n' "$1" > "$file"
          restart
        }

        status() {
          if [ -f "$file" ]; then
            echo "keep-awake: $(wanted), set $(/bin/date -r "$file" +%FT%T%z)"
          else
            echo "keep-awake: $(wanted), this Mac's default"
          fi
          echo "agent: $(/bin/launchctl print "gui/$(id -u)/$label" 2> /dev/null | /usr/bin/awk '$1 == "state" { print $3; exit }' | grep . || echo "not loaded")"
          held=$(/usr/bin/pmset -g assertions | grep 'caffeinate' | sed 's/^ */  /')
          echo "assertions:"
          echo "''${held:-  none from caffeinate}"
          echo "screen: $(/usr/sbin/ioreg -n Root -d1 | grep -q 'CGSSessionScreenIsLocked"=Yes' && echo LOCKED || echo unlocked)"
          echo "lid: $(/usr/sbin/ioreg -r -k AppleClamshellState -d 4 | grep -q '"AppleClamshellState" = Yes' && echo closed || echo open)"
          echo "power: $(/usr/bin/pmset -g batt | sed -n "s/.*'\(.*\)'.*/\1/p"), $(/usr/bin/pmset -g batt | grep -o '[0-9]*%' | head -1)"
          echo "pmset: $(/usr/bin/pmset -g | /usr/bin/awk '$1 ~ /^(sleep|displaysleep|disablesleep|lidwake|womp)$/ { printf "%s %s  ", $1, $2 }')"
          /usr/sbin/sysadminctl -screenLock status 2>&1 | sed 's/.*\] //' | tail -1
        }

        case "''${1:-status}" in
          agent)
            while :; do
              if [ "$(wanted)" = on ]; then
                /usr/bin/caffeinate -d -i -m -s -u -t 30
              else
                /bin/sleep 30
              fi
            done
            ;;
          on | off)
            set_to "$1"
            status
            ;;
          sleep)
            set_to off
            /usr/bin/nohup /bin/sh -c '/bin/sleep 3; /usr/bin/pmset sleepnow' > /dev/null 2>&1 &
            echo "keep-awake off, sleeping in 3 s; it stays off until keepawake on"
            ;;
          status) status ;;
          *)
            echo "usage: butler-keepawake [status|on|off|sleep]" >&2
            exit 2
            ;;
        esac
      '';
    in
    {
      home.packages = [ keepawake ];

      # caffeinate holds display, idle, disk and AC system sleep off, and declares the user active, for 30 s at a
      # time, so neither the screen saver nor display sleep ever starts, and the lock that follows them never comes.
      launchd.agents.butler-keepawake = {
        enable = true;

        config = {
          Label = "butler-keepawake";
          ProgramArguments = [
            "${keepawake}/bin/butler-keepawake"
            "agent"
          ];
          RunAtLoad = true;
          KeepAlive = true;
        };
      };
    };

  darwinSystemModule = {
    services.openssh = {
      enable = true;
      extraConfig = ''
        PasswordAuthentication no
        KbdInteractiveAuthentication no
      '';
    };

    users.users.${host.username}.openssh.authorizedKeys.keys = [
      ''from="${spike}",restrict,port-forwarding,permitopen="127.0.0.1:5900" ${butlerKey}''
    ];

    environment.etc."pf.anchors/butler-access".text = ''
      pass in quick on lo0 proto tcp to port 5900
      block drop in quick proto tcp to port 5900
    '';

    launchd.daemons.butler-access-pf.serviceConfig = {
      ProgramArguments = [
        "/bin/sh"
        "-c"
        loadRules
      ];
      RunAtLoad = true;
      StartInterval = 60;
      WatchPaths = [ rules ];
    };

    system.activationScripts.postActivation.text = lib.mkAfter ''
      echo "letting butler on spike drive this Mac" >&2
      /sbin/pfctl -q -a ${anchor} -f ${rules} 2> /dev/null
      /sbin/pfctl -q -E 2> /dev/null
      /sbin/pfctl -a ${anchor} -s rules 2> /dev/null | grep -q "block drop in quick proto tcp from any to any port = 5900"

      defaults write ${remoteManagement} VNCLegacyConnectionsEnabled -bool true
      defaults write ${remoteManagement} VNCAlwaysStartOnConsole -bool true

      if [ ! -s ${passwordFile} ] || [ ! -s /Library/Preferences/com.apple.VNCSettings.txt ]; then
        /usr/bin/sudo -u ${host.username} /bin/mkdir -p -m 700 ${dirOf passwordFile}
        password=$(/usr/bin/openssl rand -base64 24 | LC_ALL=C tr -dc 'A-Za-z0-9' | cut -c 1-8)
        ${kickstart} -configure -clientopts -setvnclegacy -vnclegacy yes -setvncpw -vncpw "$password" > /dev/null
        printf '%s\n' "$password" | /usr/bin/sudo -u ${host.username} /bin/sh -c 'umask 077; cat > ${passwordFile}'
        pkill -x screensharingd || true
      fi

      launchctl enable system/com.apple.screensharing
      launchctl print system/com.apple.screensharing > /dev/null 2>&1 \
        || launchctl bootstrap system /System/Library/LaunchDaemons/com.apple.screensharing.plist
    '';
  };
}
