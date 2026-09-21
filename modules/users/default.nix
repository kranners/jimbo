{ host, ... }:
{
  darwinSystemModule = {
    users.users.${host.username} = {
      name = host.username;
      home = "/Users/${host.username}";
    };

    system.primaryUser = host.username;
  };

  nixosSystemModule = { pkgs, ... }: {
    users.defaultUserShell = pkgs.zsh;

    users.users.${host.username} = {
      isNormalUser = true;
      description = "Aaron";

      shell = pkgs.zsh;

      extraGroups = [ "networkmanager" "wheel" "docker" ];
    };
  };
}
