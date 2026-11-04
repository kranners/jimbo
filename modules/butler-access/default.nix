{ host, lib, ... }:
let
  butlerKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICGnAjeBfFUnArQrUvixG5Sq07j/JdkwyyS2P8jYl7sj butler@spike-macs";
  spike = "10.100.0.1";
  spikeEndpoint = "spike.cute.engineer:51820";
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
  # Aaron asked for piggys-MBP, his own Mac, never to lock by itself while it sits idle, so butler is never locked out
  # of it overnight: no screen saver, and no password after the screen saver or display sleep. Set this false to bring
  # the idle lock back; the lid-close lock and FileVault at boot are untouched either way. pilot keeps its employer's.
  idleLockOff = host.hostname == "piggys-MBP";
  authorizedKey = ''from="${spike}",restrict,port-forwarding,permitopen="127.0.0.1:5900" ${butlerKey}'';
  helperPort = (import ./helper.nix).port;
  tokenFile = "${home}/.local/state/butler-access/hammerspoon-token";

  # spike's remote-desk gateway, for Aaron's iPad: its key reaches VNC alone, like butler's, but its forced command
  # only prints whether the screen is locked, so it runs nothing else.
  remoteDesk = import ./remote-desk.nix;
  remoteDeskKeys =
    options: status:
    lib.optional (
      remoteDesk.publicKey != null
    ) ''from="${spike}",restrict,${options}command="${status}" ${remoteDesk.publicKey}'';
in
{
  darwinHomeModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      overlay = import ./overlay {
        inherit pkgs lib;
        inherit (import ./overlay/settings.nix) idle busy;
        home = config.home.homeDirectory;
      };

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
          echo "screen saver after: $(/usr/bin/defaults -currentHost read com.apple.screensaver idleTime 2> /dev/null || echo "macOS's default") s"
          if [ -s "$HOME/.local/state/butler-access/last-lock" ]; then
            echo "last lock: $(/usr/bin/cut -f 2- "$HOME/.local/state/butler-access/last-lock" | tr '\t' ' ')"
          fi
        }

        case "''${1:-status}" in
          agent)
            # Each caffeinate outlives the next one's start by 10 s, so the assertions never lapse between runs, as
            # they could while one run ended and the next began; launchd's KeepAlive restarts the loop itself.
            trap '/bin/kill $(jobs -p) 2> /dev/null; exit 0' TERM INT
            while :; do
              if [ "$(wanted)" = on ]; then
                /usr/bin/caffeinate -d -i -m -s -u -t 40 &
              fi
              /bin/sleep 30 &
              wait $!
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

      # The WireGuard app leaves a tunnel down after a restart unless On-Demand is set in its own settings, which no
      # config here reaches, so this agent reconnects whichever WireGuard tunnel ends at spike, found by its endpoint
      # rather than a name each Mac gave it. The app runs one tunnel at a time, so while any other is up it waits.
      tunnel = pkgs.writeShellScript "butler-tunnel" ''
        set -u
        tunnels=$(/usr/sbin/scutil --nc list | /usr/bin/grep -F com.wireguard.macos)
        printf '%s\n' "$tunnels" | /usr/bin/grep -qE '[(](Connected|Connecting)[)]' && exit 0
        printf '%s\n' "$tunnels" | /usr/bin/awk '{ print $3 }' | while read -r id; do
          /usr/sbin/scutil --nc show "$id" | /usr/bin/grep -qF 'RemoteAddress : ${spikeEndpoint}' || continue
          [ "$(/usr/sbin/scutil --nc status "$id" | /usr/bin/head -1)" = Disconnected ] || continue
          echo "$(/bin/date +%FT%T%z) reconnecting $id to spike"
          /usr/sbin/scutil --nc start "$id"
        done
      '';
    in
    {
      home.packages = [
        keepawake
        overlay.command
      ];

      launchd.agents.butler-tunnel = {
        enable = true;

        config = {
          Label = "butler-tunnel";
          ProgramArguments = [ "${tunnel}" ];
          RunAtLoad = true;
          StartInterval = 60;
          StandardOutPath = "${home}/Library/Logs/butler-tunnel.log";
          StandardErrorPath = "${home}/Library/Logs/butler-tunnel.log";
        };
      };

      # Butler in a porthole at the top right, narrating in speech bubbles while butler drives this Mac.
      launchd.agents.butler-overlay = overlay.agent;

      # butler's helper runs inside Hammerspoon, a Developer ID signed app whose Accessibility and Screen Recording
      # grants follow its signature through every update, where a helper built in the Nix store would lose them on
      # each rebuild. Its config lives under ~/.config, so it never touches a ~/.hammerspoon of Aaron's own.
      xdg.configFile = {
        "hammerspoon/init.lua".text = ''
          -- Written by jimbo's butler-access module.
          dofile(hs.configdir .. "/butler.lua")
        '';
        "hammerspoon/butler.lua".text = builtins.replaceStrings [ "@port@" ] [ (toString helperPort) ] (
          builtins.readFile ./butler.lua
        );
      };

      targets.darwin.defaults."org.hammerspoon.Hammerspoon" = {
        MJConfigFile = "~/.config/hammerspoon/init.lua";
        MJShowDockIconKey = false;
        HSUploadCrashData = false;
        SUEnableAutomaticChecks = false;
      };

      # The helper answers only requests carrying this token, which only Aaron's account, and butler through his ssh
      # login, can read. It is a curl header line, so it never shows in a process list.
      home.activation.butlerHelperToken = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        if [ ! -s ${tokenFile} ]; then
          run /bin/mkdir -p -m 700 ${dirOf tokenFile}
          (umask 077; printf 'X-Butler-Token: %s\n' "$(/usr/bin/openssl rand -hex 24)" > ${tokenFile})
        fi
      '';

      # The screen saver never starts, so nothing idle locks the screen behind it, in the ByHost domain macOS reads
      # it from and the user domain, and the activation says when macOS's own lock after display sleep is still on,
      # which only `sysadminctl -screenLock off -password -`, typed by Aaron, turns off.
      targets.darwin.currentHostDefaults."com.apple.screensaver" = lib.mkIf idleLockOff {
        idleTime = 0;
        askForPassword = 0;
        askForPasswordDelay = 0;
      };
      targets.darwin.defaults."com.apple.screensaver" = lib.mkIf idleLockOff {
        askForPassword = 0;
        askForPasswordDelay = 0;
      };
      home.activation.butlerIdleLock = lib.mkIf idleLockOff (
        lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          if ! /usr/sbin/sysadminctl -screenLock status 2>&1 | grep -q 'screenLock is off'; then
            echo "butler-access: this Mac still locks after display sleep; run: sysadminctl -screenLock off -password -" >&2
          fi
        ''
      );

      launchd.agents.hammerspoon = {
        enable = true;

        config = {
          ProgramArguments = [ "/Applications/Hammerspoon.app/Contents/MacOS/Hammerspoon" ];
          RunAtLoad = true;
          KeepAlive = true;
        };
      };

      # caffeinate holds display, idle, disk and AC system sleep off, and declares the user active, in overlapping
      # 40 s runs started every 30 s, so neither the screen saver nor display sleep ever starts, and the lock that
      # follows them never comes.
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
    {
      homebrew.casks = [ "hammerspoon" ];

      services.openssh = {
        enable = true;
        extraConfig = ''
          PasswordAuthentication no
          KbdInteractiveAuthentication no
        '';
      };

      users.users.${host.username}.openssh.authorizedKeys.keys = [
        authorizedKey
      ]
      ++ remoteDeskKeys ''port-forwarding,permitopen="127.0.0.1:5900",'' (
        pkgs.writeShellScript "remote-desk-status" ''
          if /usr/sbin/ioreg -n Root -d1 | /usr/bin/grep -q 'CGSSessionScreenIsLocked"=Yes'; then
            echo locked
          elif [ "$(/usr/bin/stat -f %Su /dev/console)" = root ]; then
            echo "at the login window"
          else
            echo unlocked
          fi
        ''
      );

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
// lib.optionalAttrs (host.hostname == "jimbo") {
  # The jimbo PC's NixOS install, the Linux half of a dual boot whose Windows half Aaron sets up by hand with
  # docs/windows-remote.ps1. butler reaches it over spike's WireGuard alone: ssh with its key, and Hyprland's screen
  # through wayvnc on a unix socket in Aaron's runtime directory, which ssh forwards.
  nixosSystemModule =
    { pkgs, ... }:
    {
      services.openssh = {
        openFirewall = false;
        settings = {
          PasswordAuthentication = false;
          KbdInteractiveAuthentication = false;
        };
      };

      users.users.${host.username}.openssh.authorizedKeys.keys = [
        authorizedKey
      ]
      # OpenSSH refuses every unix-socket forward to a key with permitopen, so this key forwards nothing, and its
      # forced command itself carries VNC from wayvnc's socket over the session when asked for `vnc`.
      ++ remoteDeskKeys "" (
        pkgs.writeShellScript "remote-desk-status" ''
          if [ "''${SSH_ORIGINAL_COMMAND:-}" = vnc ]; then
            exec ${pkgs.socat}/bin/socat STDIO UNIX-CONNECT:/run/user/$(id -u)/butler-wayvnc.sock
          fi
          if ${pkgs.procps}/bin/pgrep -x hyprlock > /dev/null; then echo locked; else echo unlocked; fi
        ''
      );

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
