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
  authorizedKey = ''from="${spike}",restrict,port-forwarding,permitopen="127.0.0.1:5900" ${butlerKey}'';
  # Root on a Mac takes the same key, but forces butler-elevated whatever command it asks for, and butler's mac
  # wrapper logs in as root only for `mac <host> elevated`, a rule the daemon always asks Aaron about.
  rootKey = elevate: ''from="${spike}",restrict,command="${elevate}" ${butlerKey}'';
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

  darwinSystemModule =
    { pkgs, ... }:
    let
      # Runs the script on stdin as root, the one thing root's key can do, logging each run to the system log.
      elevate = pkgs.writeShellScript "butler-elevated" ''
        /usr/bin/logger -t butler-elevated "running a script from butler on spike, approved by Aaron in Discord"
        export PATH=/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
        cd /var/root || exit 1
        exec /bin/sh -s
      '';
    in
    {
      services.openssh = {
        enable = true;
        extraConfig = ''
          PasswordAuthentication no
          KbdInteractiveAuthentication no
          PermitRootLogin forced-commands-only
        '';
      };

      users.users.${host.username}.openssh.authorizedKeys.keys = [ authorizedKey ];
      users.users.root.openssh.authorizedKeys.keys = [ (rootKey elevate) ];

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

        # Remote Login limited to some users keeps them in com.apple.access_ssh, which root then joins.
        if dscl . -read /Groups/com.apple.access_ssh > /dev/null 2>&1 \
          && ! dseditgroup -o checkmember -m root com.apple.access_ssh > /dev/null 2>&1; then
          dseditgroup -o edit -a root -t user com.apple.access_ssh \
            || echo "could not let root use Remote Login, so mac elevated is refused here" >&2
        fi
      '';
    };
}
// lib.optionalAttrs (host.hostname == "jimbo") {
  # The jimbo PC's NixOS install, the Linux half of a dual boot whose Windows half Aaron sets up by hand with
  # docs/windows-remote.ps1. butler reaches it over spike's WireGuard alone: ssh with its key, and Hyprland's screen
  # through wayvnc on a unix socket in Aaron's runtime directory, which ssh forwards.
  nixosSystemModule = {
    services.openssh = {
      openFirewall = false;
      settings = {
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
      };
    };

    users.users.${host.username}.openssh.authorizedKeys.keys = [ authorizedKey ];

    networking.firewall.extraCommands = ''
      iptables -A nixos-fw -i wg0 -s ${spike} -p tcp --dport 22 -j nixos-fw-accept
    '';
  };

  nixosHomeModule =
    { pkgs, ... }:
    let
      jq = "${pkgs.jq}/bin/jq";

      # The Hyprland session's environment, for commands that arrive over ssh.
      sessionEnv = ''
        export XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
        eval "$(systemctl --user show-environment 2> /dev/null | grep -E '^(WAYLAND_DISPLAY|HYPRLAND_INSTANCE_SIGNATURE|DISPLAY|XDG_CURRENT_DESKTOP)=' | sed 's/^/export /')"
      '';

      desktop = pkgs.writeShellScriptBin "butler-desktop" ''
        set -u
        ${sessionEnv}
        case "''${1:-}" in
          env)
            env | grep -E '^(XDG_RUNTIME_DIR|WAYLAND_DISPLAY|HYPRLAND_INSTANCE_SIGNATURE|DISPLAY|XDG_CURRENT_DESKTOP)=' | sed "s/=\(.*\)/='\1'/; s/^/export /"
            ;;
          windows)
            if [ -z "''${HYPRLAND_INSTANCE_SIGNATURE:-}" ] || ! hyprctl version > /dev/null 2>&1; then
              echo "Hyprland is not running" >&2
              exit 1
            fi
            echo "front: $(hyprctl activewindow -j | ${jq} -r 'if .class then "\(.class), \(.title)" else "none" end')"
            hyprctl monitors -j | ${jq} -r '.[] | "screen: \(.name) \(.width)x\(.height) pixels at \(.x),\(.y), scale \(.scale), workspace \(.activeWorkspace.name)\(if .focused then ", focused" else "" end)"'
            echo "windows, most recently focused first, as class, workspace, state, x,y widthxheight in layout pixels, title:"
            hyprctl clients -j | ${jq} -r 'sort_by(.focusHistoryID) | .[] | select(.mapped) | "  \(.class), workspace \(.workspace.name), \(if .hidden then "hidden" elif (.fullscreen | tostring) != "0" and (.fullscreen | tostring) != "false" then "fullscreen" elif .floating then "floating" else "tiled" end), \(.at[0]),\(.at[1]) \(.size[0])x\(.size[1]), \(.title)"'
            ;;
          *)
            echo "usage: butler-desktop env|windows" >&2
            exit 2
            ;;
        esac
      '';

      keepawake = pkgs.writeShellScriptBin "butler-keepawake" ''
        set -u
        ${sessionEnv}
        file="$HOME/.local/state/butler-access/keepawake"

        wanted() {
          case "$(cat "$file" 2> /dev/null)" in
            off) echo off ;;
            *) echo on ;;
          esac
        }

        set_to() {
          mkdir -p "$(dirname "$file")"
          printf '%s\n' "$1" > "$file"
          systemctl --user restart butler-keepawake 2> /dev/null \
            || echo "could not restart butler-keepawake; it takes the change within 30 s"
        }

        status() {
          if [ -f "$file" ]; then
            echo "keep-awake: $(wanted), set $(date -r "$file" +%FT%T%z)"
          else
            echo "keep-awake: $(wanted), this PC's default"
          fi
          echo "agent: $(systemctl --user is-active butler-keepawake)"
          echo "screen sharing: $(systemctl --user is-active butler-wayvnc)"
          echo "screen: $(pgrep -x hyprlock > /dev/null && echo LOCKED || echo unlocked)"
          echo "inhibitors:"
          systemd-inhibit --list --no-pager --no-legend 2> /dev/null | sed 's/^/  /' | grep . || echo "  none"
        }

        case "''${1:-status}" in
          agent)
            while :; do
              if [ "$(wanted)" = on ]; then
                systemd-inhibit --what=idle:sleep --who=butler-keepawake --why="butler may be driving this PC" --mode=block sleep 30
              else
                sleep 30
              fi
            done
            ;;
          on | off)
            set_to "$1"
            status
            ;;
          sleep)
            set_to off
            sudo -n systemd-run --quiet --on-active=3 systemctl suspend
            echo "keep-awake off, sleeping in 3 s; it stays off until keepawake on, and only Aaron can wake it, since it has no Wake-on-LAN over Wi-Fi"
            ;;
          status) status ;;
          *)
            echo "usage: butler-keepawake [status|on|off|sleep]" >&2
            exit 2
            ;;
        esac
      '';

      # Restarts into the other install once, through the firmware's BootNext, or systemd-boot's one-shot entry when
      # the firmware has no Windows Boot Manager of its own.
      boot = pkgs.writeShellScriptBin "butler-boot" ''
        set -u
        if [ "''${1:-}" != windows ] || { [ "''${2:-}" != plan ] && [ "''${2:-}" != go ]; }; then
          echo "usage: butler-boot windows plan|go" >&2
          exit 2
        fi
        entry=$(sudo -n ${pkgs.efibootmgr}/bin/efibootmgr | sed -n 's/^Boot\([0-9A-Fa-f]\{4\}\)\*\{0,1\} \(Windows Boot Manager\).*/\1/p' | head -1)
        if [ -n "$entry" ]; then
          echo "from Linux: next boot only, start the firmware entry Boot$entry Windows Boot Manager (efibootmgr --bootnext $entry), then reboot in 5 s"
          set_next() { sudo -n ${pkgs.efibootmgr}/bin/efibootmgr --bootnext "$entry" > /dev/null; }
        elif bootctl list --no-pager 2> /dev/null | grep -q 'id: auto-windows'; then
          echo "from Linux: next boot only, systemd-boot's auto-windows entry (bootctl set-oneshot auto-windows), then reboot in 5 s"
          set_next() { sudo -n bootctl set-oneshot auto-windows; }
        else
          echo "found no Windows entry in the firmware boot menu or in systemd-boot"
          exit 3
        fi
        if [ "$2" = go ]; then
          set_next || { echo "could not set the next boot" >&2; exit 1; }
          sudo -n systemd-run --quiet --on-active=5 systemctl reboot
          echo "rebooting into Windows in 5 s"
        fi
      '';
    in
    {
      home.packages = [
        desktop
        keepawake
        boot
      ];

      systemd.user.services = {
        # Holds idle and sleep off for 30 s at a time while keep-awake is on, so it follows the file within 30 s.
        butler-keepawake = {
          Unit.Description = "Keep the PC awake for butler";
          Service = {
            ExecStart = "${keepawake}/bin/butler-keepawake agent";
            Restart = "always";
          };
          Install.WantedBy = [ "default.target" ];
        };

        # The socket sits in the 0700 runtime directory, so only Aaron, and butler through his ssh login, reach it.
        butler-wayvnc = {
          Unit = {
            Description = "Hyprland's screen for butler, over VNC on a unix socket";
            PartOf = [ "graphical-session.target" ];
            After = [ "graphical-session.target" ];
          };
          Service = {
            UMask = "0077";
            ExecStartPre = "${pkgs.coreutils}/bin/rm -f %t/butler-wayvnc.sock";
            ExecStart = "${pkgs.wayvnc}/bin/wayvnc --render-cursor --keyboard=us unix:%t/butler-wayvnc.sock";
            Restart = "on-failure";
            RestartSec = 5;
          };
          Install.WantedBy = [ "graphical-session.target" ];
        };
      };
    };
}
