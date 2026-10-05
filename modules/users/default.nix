{ host, lib, ... }:
{
  darwinSystemModule = {
    users.users.${host.username} = {
      name = host.username;
      home = "/Users/${host.username}";
    };

    system.primaryUser = host.username;
  };

  nixosSystemModule =
    { config, pkgs, ... }:
    {
      users.defaultUserShell = pkgs.zsh;

      users.users.${host.username} = {
        isNormalUser = true;
        description = "Aaron";

        shell = pkgs.zsh;

        extraGroups = [
          "networkmanager"
          "wheel"
        ]
        # The group only exists on hosts that run Docker, and naming one that
        # does not is a warning from useradd on every switch.
        ++ lib.optional config.virtualisation.docker.enable "docker";
      };
    };
}
