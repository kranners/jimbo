{ host, ... }:
{
  nixosSystemModule =
    { pkgs, ... }:
    {
      imports = [
        ./hardware.nix
        ./watchdog.nix
      ];

      boot.loader.systemd-boot.enable = true;
      boot.loader.systemd-boot.configurationLimit = 5;
      boot.loader.efi.canTouchEfiVariables = true;

      networking.hostName = host.hostname;

      users.users.${host.username}.openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFTgNyfuTRL/Kygs5zNODcjMpcT/69U91T7nrOOHrbju"
      ];

      environment.systemPackages = [ pkgs.vim ];

      services.openssh.settings.PasswordAuthentication = false;

      services.avahi = {
        enable = true;
        openFirewall = true;
        publish = {
          enable = true;
          addresses = true;
        };
      };

      system.stateVersion = "26.05";
    };

  nixosHomeModule.home.stateVersion = "26.11";
}
