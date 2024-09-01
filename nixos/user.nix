{ pkgs, ... }: {
  users = {
    defaultUserShell = pkgs.zsh;

    users.aaron = {
      isNormalUser = true;
      description = "Aaron";

      shell = pkgs.zsh;
      extraGroups = [ "networkmanager" "wheel" ];
    };
  };

  security.sudo.wheelNeedsPassword = false;

  environment.variables.EDITOR = "vim";

  home = {
    home = {
      username = "aaron";
      homeDirectory = "/home/aaron";
    };

    xdg = {
      enable = true;
      userDirs = {
        createDirectories = true;
        enable = true;
      };
    };
  };
}
