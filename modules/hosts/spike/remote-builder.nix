{ config, lib, ... }:
let
  framerRootKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPoWozpVYjlIOVm0mFTkiz/Ni6RzF6WZfddDtetwPMzu root@framer";

  # spike sends its own builds, jimbo-switch's among them, to the NUC once Aaron turns this on, after the NUC is spike's
  # WireGuard peer and its builder role is on: root's key /var/lib/secrets/nuc-builder-key, made by hand here, goes in the
  # NUC's nuc.builder.clientKeys, and the NUC's host key, from `cat /etc/ssh/ssh_host_ed25519_key.pub` there, in hostKey.
  nucBuilder = {
    enable = false;
    hostKey = null;
  };
in
{
  users.users.nix-builder = {
    isSystemUser = true;
    group = "nix-builder";
    useDefaultShell = true;
    openssh.authorizedKeys.keys = [
      ''command="${config.nix.package}/bin/nix-daemon --stdio",restrict ${framerRootKey}''
    ];
  };

  users.groups.nix-builder = { };

  nix.settings.trusted-users = [ "nix-builder" ];

  nix.daemonCPUSchedPolicy = "idle";
  nix.daemonIOSchedClass = "idle";

  nix.distributedBuilds = lib.mkIf nucBuilder.enable true;
  nix.settings.builders-use-substitutes = lib.mkIf nucBuilder.enable true;
  nix.buildMachines = lib.mkIf nucBuilder.enable [
    {
      hostName = "10.100.0.14";
      sshUser = "nix-builder";
      sshKey = "/var/lib/secrets/nuc-builder-key";
      protocol = "ssh-ng";
      system = "x86_64-linux";
      maxJobs = 4;
      supportedFeatures = [
        "nixos-test"
        "benchmark"
        "big-parallel"
        "kvm"
      ];
    }
  ];
  programs.ssh.knownHosts = lib.mkIf (nucBuilder.enable && nucBuilder.hostKey != null) {
    nuc = {
      hostNames = [ "10.100.0.14" ];
      publicKey = nucBuilder.hostKey;
    };
  };
}
