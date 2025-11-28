{
  darwinSystemModule = {
    users.users.aaron = {
      name = "aaron";
      home = "/Users/aaron";
    };

    system.primaryUser = "aaron";
  };

  nixosSystemModule = { pkgs, ... }: {
    users.defaultUserShell = pkgs.zsh;

    users.users.aaron = {
      isNormalUser = true;
      description = "Aaron";

      shell = pkgs.zsh;

      extraGroups = [ "networkmanager" "wheel" "docker" ];
    };
  };
}
