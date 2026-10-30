{ host, lib, ... }:
{
  nixosSystemModule =
    { pkgs, ... }:
    {
      imports = [
        ./hardware.nix
        ./backlogic.nix
        ./backlogic-tunnel.nix
        ./bowerbird.nix
        ./butler.nix
        ./butler-drive.nix
        ./butler-mail.nix
        ./butler-messenger.nix
        ./butler-outlook.nix
        ./butler-reminders.nix
        ./butler-tools.nix
        ./butler-voice.nix
        ./caddy.nix
        ./claude.nix
        ./dns.nix
        ./docker.nix
        ./environments.nix
        ./framer-vnc.nix
        ./home-assistant.nix
        ./messenger.nix
        ./mise.nix
        ./monitoring.nix
        ./voice.nix
        ./watchdog.nix
        ./remote-builder.nix
        ./tmp.nix
        ./wireguard.nix
      ];

      boot.loader.systemd-boot.enable = true;
      boot.loader.efi.canTouchEfiVariables = true;

      networking.hostName = host.hostname;

      users.users.${host.username}.openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKMkmFNbJsrIYrkDs5/1OO9lIOU/ZDiDVvHs8kR8Rq7K"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFTgNyfuTRL/Kygs5zNODcjMpcT/69U91T7nrOOHrbju"
      ];

      users.users.rylee = {
        isNormalUser = true;
        description = "Rylee";
        extraGroups = [
          "wheel"
          "docker"
        ];
        openssh.authorizedKeys.keys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICajNcJKs5Iv63ZNppww4tNmNjkMjbPJwX2trSPiLGeT"
        ];
      };

      nix.gc.dates = "daily";

      programs.git.enable = true;

      environment.systemPackages = [ pkgs.vim ];

      services.openssh.settings.PasswordAuthentication = false;

      services.avahi = {
        enable = true;
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

      zramSwap.enable = true;

      services.journald.settings.Journal.SystemMaxUse = "1G";

      system.stateVersion = "26.05";
    };

  nixosHomeModule.home.stateVersion = "26.11";
  nixosHomeModule.home.file = lib.genAttrs [ ".claude/CLAUDE.md" ".claude-work/CLAUDE.md" ] (_: {
    text = lib.mkAfter (builtins.readFile ./CLAUDE.md);
  });
}
