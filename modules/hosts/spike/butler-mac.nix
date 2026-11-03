{
  config,
  lib,
  pkgs,
  ...
}:
let
  python = pkgs.python3Packages;

  addressOf =
    name:
    lib.removeSuffix "/32" (
      lib.head
        (lib.findFirst (peer: peer.name == name) null config.networking.wireguard.interfaces.wg0.peers)
        .allowedIPs
    );

  hosts = {
    pilot = {
      address = addressOf "pilot";
      user = "aaronpierce";
    };
    piggys-MBP = {
      address = addressOf "piggys-MBP";
      user = "aaron";
    };
  };

  substitutions = {
    "@hosts@" = builtins.toJSON hosts;
    "@ssh@" = lib.getExe pkgs.openssh;
    "@ffmpeg@" = lib.getExe pkgs.ffmpeg-headless;
    "@outbox@" = "${config.users.users.butler.home}/outbox";
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
      See and drive Aaron's MacBooks, pilot and piggys-MBP, as he watches: his real screen, mouse and keyboard over Screen Sharing, and a shell over ssh.
      mac hosts | mac log [count] | mac <host> look | mac <host> click <x> <y> [left|right|middle|double] | mac <host> move <x> <y> | mac <host> drag <x1> <y1> <x2> <y2> | mac <host> scroll <x> <y> <up|down> [clicks] | mac <host> type [text] (or text on stdin) | mac <host> key <combo> [combo...] | mac <host> run [shell words] (or a script on stdin, for anything with a dash) | mac <host> record start | mac <host> record stop | mac <host> keepawake [status|on|off] | mac <host> sleep
      keepawake on holds the Mac awake and unlocked, keepawake off lets it idle-sleep and lock as usual, and sleep turns it off and sleeps the Mac now.
      Every action but run, record, keepawake and sleep prints the outbox path of a fresh screenshot to read or attach with attach_file; x and y are pixels of that picture.
    '';
    stdin = true;
    rules = [
      {
        match = [ "**" ];
        lanes = [ "interactive" ];
        egress = true;
      }
    ];
    credentials.butler-mac-key = "/var/lib/secrets/butler-mac-key";
    skill = ./butler-skills/mac;
  };
}
