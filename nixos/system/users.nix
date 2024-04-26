{ config, pkgs, inputs, ... }: {
  users.defaultUserShell = pkgs.zsh;

  users.users.aaron = {
    isNormalUser = true;
    description = "Aaron";

    shell = pkgs.zsh;

    extraGroups = [ "networkmanager" "wheel" ];
  };

  security.sudo.wheelNeedsPassword = false;
}
