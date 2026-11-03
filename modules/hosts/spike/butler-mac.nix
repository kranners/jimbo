{
  config,
  lib,
  pkgs,
  ...
}:
let
  python = pkgs.python3Packages;

  peer =
    name: lib.findFirst (peer: peer.name == name) null config.networking.wireguard.interfaces.wg0.peers;
  addressOf = name: lib.removeSuffix "/32" (lib.head (peer name).allowedIPs);

  hosts = {
    pilot = {
      os = "macos";
      address = addressOf "pilot";
      user = "aaronpierce";
    };
    piggys-MBP = {
      os = "macos";
      address = addressOf "piggys-MBP";
      user = "aaron";
    };
    # The jimbo PC dual boots, so it answers as whichever install is up. Its Linux install joins once spike has its
    # WireGuard key, `jimbo` in ./wireguard.nix.
    jimbo.systems =
      lib.optional (peer "jimbo" != null) {
        os = "linux";
        address = addressOf "jimbo";
        user = "aaron";
      }
      ++ [
        {
          os = "windows";
          address = addressOf "windows";
          user = "aaron";
        }
      ];
  };

  substitutions = {
    "@hosts@" = builtins.toJSON hosts;
    "@ssh@" = lib.getExe pkgs.openssh;
    "@ffmpeg@" = lib.getExe pkgs.ffmpeg-headless;
    "@outbox@" = "${config.users.users.butler.home}/outbox";
    "@windowsScreenshot@" = "${../../../docs/windows-screenshot.ps1}";
    "@helperPort@" = toString (import ../../butler-access/helper.nix).port;
  };

  mac =
    pkgs.writers.writePython3Bin "mac"
      {
        libraries = [
          python.vncdotool
          python.pillow
        ];
        flakeIgnore = [ "E501" ];
      }
      (
        builtins.replaceStrings (lib.attrNames substitutions) (lib.attrValues substitutions) (
          builtins.readFile ./butler-mac/mac.py
        )
      );
in
{
  butler.commands.mac = {
    package = mac;
    description = ''
      See and drive Aaron's MacBooks, pilot and piggys-MBP, and his dual-boot PC jimbo, as he watches: his real screen, mouse and keyboard over VNC, and a shell over ssh.
      mac hosts | mac log [count] | mac <host> look | mac <host> click <x> <y> [left|right|middle|double] | mac <host> move <x> <y> | mac <host> drag <x1> <y1> <x2> <y2> | mac <host> scroll <x> <y> <up|down> [clicks] | mac <host> type [text] (or text on stdin) | mac <host> key <combo> [combo...] | mac <host> windows | mac <host> run [shell words] (or a script on stdin, for anything with a dash) | mac <host> record start | mac <host> record stop | mac <host> keepawake [status|on|off] | mac <host> sleep | mac jimbo boot <linux|windows> [confirm]
      jimbo runs NixOS with Hyprland or Windows, one at a time: mac hosts says which is up, run takes sh on Linux and PowerShell on Windows, it has no cmd key (use ctrl and super), and boot restarts it into the other only when Aaron asks, never past a login or disk-encryption screen.
      windows lists the front app, the running apps and every window front to back with its place and size, so you can open, focus, switch, resize, minimise, close and quit apps and windows; the mac skill has the recipes.
      On the Macs: mac <host> menu <app|front> [menu] [item...] | mac <host> dialog [app] | mac <host> press <number|name> [app] | mac <host> focus <number|name> [app] | mac <host> displays | mac <host> display <n> [look] | mac <host> display <n> click <x> <y> [left|right|double] | mac <host> window <rectangle action> | mac <host> window display <n>
      menu lists an app's menus or chooses an item by name, dialog numbers the front window's buttons and fields for press and focus, displays and display see and click every screen, not just the main one look shows, and window snaps or moves the front window with Rectangle; the only stop is a password or Touch ID prompt, which goes to Aaron.
      keepawake on holds the machine awake and unlocked, keepawake off lets it idle-sleep and lock as usual, and sleep turns it off and sleeps it now.
      Every action but windows, run, record, keepawake, sleep and boot prints the outbox path of a fresh screenshot to read or attach with attach_file; x and y are pixels of that picture.
    '';
    stdin = true;
    rules = [
      {
        match = [ "**" ];
        lanes = [ "interactive" ];
        egress = true;
        # A thread Aaron typed drives his machines without his button, even after reading private data; one a voice request began still asks.
        trusted = true;
      }
    ];
    credentials.butler-mac-key = "/var/lib/secrets/butler-mac-key";
    skill = ./butler-skills/mac;
  };
}
