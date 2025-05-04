{ pkgs, ... }: {
  users.defaultUserShell = pkgs.zsh;
  programs.zsh.enable = true;

  users.users.aaron = {
    isNormalUser = true;
    description = "Aaron";

    shell = pkgs.zsh;

    extraGroups = [
      "networkmanager"
      "wheel"
      "vboxusers"
    ];
  };

  security.sudo.wheelNeedsPassword = false;
}
