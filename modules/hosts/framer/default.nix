{ host, ... }:
{
  kiosk.url = "http://spike.local:8123/nixos-lovelace/panel";
  kiosk.versionUrl = "http://spike.local:8123/local/panel-version";
  kiosk.output = "eDP-1";
  kiosk.scale = 2;
  kiosk.transform = "90";
  kiosk.lanInterface = "wlp1s0";

  nixosSystemModule =
    { pkgs, ... }:
    {
      imports = [
        ./hardware.nix
        ./watchdog.nix
        ./wireguard.nix
        ./monitoring.nix
        ./voice.nix
        ./openclaw
        ./remote-builder.nix
        ./email.nix
        ./google-calendar.nix
        ./google-tasks.nix
        ./github-issues.nix
        ./backlogic.nix
        ./panel.nix
        ./surface.nix
      ];

      boot.loader.systemd-boot.enable = true;
      boot.loader.systemd-boot.configurationLimit = 5;
      boot.loader.efi.canTouchEfiVariables = true;

      networking.hostName = host.hostname;

      users.users.${host.username}.openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKMkmFNbJsrIYrkDs5/1OO9lIOU/ZDiDVvHs8kR8Rq7K"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFTgNyfuTRL/Kygs5zNODcjMpcT/69U91T7nrOOHrbju"
      ];

      environment.systemPackages = [ pkgs.vim ];

      services.openssh.settings.PasswordAuthentication = false;

      services.avahi = {
        enable = true;
        nssmdns4 = true;
        # https://github.com/avahi/avahi/issues/117
        settings.server.use-ipv6 = false;
        openFirewall = true;
        settings.publish = {
          disable-publishing = false;
          publish-addresses = true;
        };
      };

      system.stateVersion = "26.05";
    };

  nixosHomeModule.home.stateVersion = "26.11";
}
