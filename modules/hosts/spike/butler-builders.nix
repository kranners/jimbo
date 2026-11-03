{
  config,
  lib,
  pkgs,
  ...
}:
let
  state = "/var/lib/butler-builders";
  memoryDeployKey = "/var/lib/secrets/butler-memory-deploy-key";
  credentials = "/run/credentials/butler-builders.service";

  substitutions = {
    "@selfFix@" = "${config.users.users.butler.home}/self-fix";
    "@kanban@" = lib.getExe config.butler.commands.kanban.package;
    "@git@" = lib.getExe pkgs.git;
  };

  builders = pkgs.writers.writePython3Bin "butler-builders" { flakeIgnore = [ "E501" ]; } (
    builtins.replaceStrings (lib.attrNames substitutions) (lib.attrValues substitutions) (
      builtins.readFile ./butler-builders/builders.py
    )
  );
in
{
  options.butler.builders.digest = lib.mkOption {
    description = "The local copy of the builders in flight digest, which the change launcher appends to each new brief.";
    type = lib.types.str;
    default = "${state}/builders.md";
    readOnly = true;
  };

  config = {
    # The digest every change session reads: what the other changes and Aaron's board sessions are changing.
    systemd.services.butler-builders = {
      description = "Rebuild the builders in flight digest of butler's changes and Aaron's board sessions";
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      unitConfig.ConditionPathExists = memoryDeployKey;
      path = [ pkgs.openssh ];
      environment = {
        GIT_SSH_COMMAND = "ssh -i ${credentials}/memory-deploy-key -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=${state}/known_hosts";
        KANBAN_KNOWN_HOSTS = "${state}/known_hosts";
      };
      serviceConfig = {
        Type = "oneshot";
        ExecStart = lib.getExe builders;
        StateDirectory = "butler-builders";
        StateDirectoryMode = "0700";
        LoadCredential = [
          "memory-deploy-key:${memoryDeployKey}"
          "butler-mac-key:/var/lib/secrets/butler-mac-key"
        ];
        TimeoutStartSec = "5min";
      };
    };

    systemd.timers.butler-builders = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnActiveSec = "2min";
        OnUnitInactiveSec = "2min";
      };
    };
  };
}
