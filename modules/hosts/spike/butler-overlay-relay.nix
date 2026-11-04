# Keeps Butler's overlay on Aaron's Mac for as long as any of butler's turns runs, whether he is working on spike, on
# a Mac or anywhere else, narrating each turn's start and the tools it moves to; see ./butler-overlay-relay/relay.py.
# It reads only the daemon's call state, which names each running turn's latest tool and never its input, and runs
# nothing on the Mac but its `butler-overlay`, over butler's Mac key, which already runs any command there as Aaron.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.butler.overlayRelay;
  peer =
    name: lib.findFirst (peer: peer.name == name) null config.networking.wireguard.interfaces.wg0.peers;
  addressOf = name: lib.removeSuffix "/32" (lib.head (peer name).allowedIPs);
  users = {
    piggys-MBP = "aaron";
    pilot = "aaronpierce";
  };

  relayConfig = {
    hosts = lib.genAttrs cfg.hosts (name: {
      address = addressOf name;
      user = users.${name};
    });
    callState = "/run/butler-call/call.json";
    overlay = "/etc/profiles/per-user/$USER/bin/butler-overlay";
    ssh = lib.getExe pkgs.openssh;
    state = "/var/lib/butler-overlay-relay";
    runtime = "/run/butler-overlay-relay";
  };

  relay = pkgs.writers.writePython3Bin "butler-overlay-relay" {
    flakeIgnore = [ "E501" ];
  } (builtins.readFile ./butler-overlay-relay/relay.py);
in
{
  options.butler.overlayRelay = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Show Butler's overlay on Aaron's Mac while any of butler's turns runs.";
    };
    hosts = lib.mkOption {
      type = lib.types.listOf (lib.types.enum (lib.attrNames users));
      default = [ "piggys-MBP" ];
      description = "The Macs whose overlay shows Butler at work; pilot only on Aaron's say-so, as his employer's Mac.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.butler-overlay-relay = {
      description = "Show Butler's overlay on Aaron's Mac while butler works";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [
        "network-online.target"
        "wireguard-wg0.service"
      ];
      environment.RELAY_CONFIG = builtins.toJSON relayConfig;
      serviceConfig = {
        ExecStart = lib.getExe relay;
        DynamicUser = true;
        LoadCredential = [ "butler-mac-key:/var/lib/secrets/butler-mac-key" ];
        StateDirectory = "butler-overlay-relay";
        RuntimeDirectory = "butler-overlay-relay";
        RuntimeDirectoryMode = "0700";
        Restart = "always";
        RestartSec = 5;
        Nice = 10;
        ProtectHome = true;
        ProtectSystem = "strict";
        PrivateTmp = true;
        NoNewPrivileges = true;
        MemoryMax = "128M";
      };
    };
  };
}
