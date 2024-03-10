{pkgs, ...}: {
  users.users.aaron = {
    isNormalUser = true;
    description = "Aaron";

    shell = pkgs.zsh;

    extraGroups = ["networkmanager" "wheel"];
  };
}
