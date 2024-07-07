{ config
, pkgs
, inputs
, ...
}: {
  users.defaultUserShell = pkgs.zsh;
  programs.zsh.enable = true;

  users.users.aaron = {
    isNormalUser = true;
    description = "Aaron";

    shell = pkgs.zsh;

    extraGroups = [ "networkmanager" "wheel" "input" ];
  };

  security.sudo.wheelNeedsPassword = false;
}
