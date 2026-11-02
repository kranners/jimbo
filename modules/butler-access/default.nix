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
in
{
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
