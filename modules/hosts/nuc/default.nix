{
  host,
  inputs,
  pkgs,
  ...
}:
let
  # The keys every host here accepts for aaron, and so for root on the installer, which nixos-anywhere logs in to.
  aaronKeys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKMkmFNbJsrIYrkDs5/1OO9lIOU/ZDiDVvHs8kR8Rq7K"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFTgNyfuTRL/Kygs5zNODcjMpcT/69U91T7nrOOHrbju"
  ];

  # The stock minimal installer with sshd up and those keys on root, so the NUC can be installed from piggys-MBP or spike without a keyboard.
  installer = inputs.nixpkgs.lib.nixosSystem {
    inherit (host) system;
    modules = [
      "${inputs.nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
      {
        image.baseName = inputs.nixpkgs.lib.mkForce "nuc-installer";
        services.openssh.enable = true;
        services.openssh.settings.PasswordAuthentication = false;
        users.users.root.openssh.authorizedKeys.keys = aaronKeys;
        networking.hostName = "nuc-installer";
      }
    ];
  };
  iso = installer.config.system.build.isoImage;
in
{
  packages.${host.system}.nuc-installer-iso = iso;

  # Evaluates the NUC's system and the installer, without building either, so a broken host fails the check cheaply.
  checks.${host.system}.nuc =
    let
      inherit (inputs.self.nixosConfigurations) nuc;
    in
    pkgs.writeText "nuc-eval" ''
      ${builtins.unsafeDiscardStringContext nuc.config.system.build.toplevel.drvPath}
      ${builtins.unsafeDiscardStringContext iso.drvPath}
    '';

  nixosSystemModule =
    { config, ... }:
    {
      imports = [
        inputs.disko.nixosModules.disko
        ./hardware.nix
        ./disko.nix
        ./network.nix
        ./wireguard.nix
        ./roles
      ];

      boot.loader.systemd-boot.enable = true;
      boot.loader.systemd-boot.configurationLimit = config.jimbo.keepGenerations;
      boot.loader.efi.canTouchEfiVariables = true;

      networking.hostName = host.hostname;

      users.users.${host.username}.openssh.authorizedKeys.keys = aaronKeys;
      services.openssh.settings.PasswordAuthentication = false;

      programs.git.enable = true;
      environment.systemPackages = [ pkgs.vim ];

      services.avahi = {
        enable = true;
        nssmdns4 = true;
        openFirewall = true;
        settings.publish = {
          disable-publishing = false;
          publish-addresses = true;
        };
      };

      systemd.targets = {
        sleep.enable = false;
        suspend.enable = false;
        hibernate.enable = false;
        hybrid-sleep.enable = false;
      };

      systemd.settings.Manager = {
        RuntimeWatchdogSec = "30s";
        RebootWatchdogSec = "5min";
      };
      boot.kernel.sysctl."kernel.panic" = 10;

      services.journald.settings.Journal.SystemMaxUse = "1G";

      # spike scrapes it over WireGuard once the NUC is its peer.
      services.prometheus.exporters.node.enable = true;
      networking.firewall.interfaces.wg0.allowedTCPPorts = [
        config.services.prometheus.exporters.node.port
      ];

      system.stateVersion = "26.05";
    };

  nixosHomeModule.home.stateVersion = "26.11";
}
