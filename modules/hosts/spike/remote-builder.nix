{ config, ... }:
let
  framerRootKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPoWozpVYjlIOVm0mFTkiz/Ni6RzF6WZfddDtetwPMzu root@framer";
in
{
  users.users.nix-builder = {
    isSystemUser = true;
    group = "nix-builder";
    useDefaultShell = true;
    openssh.authorizedKeys.keys = [
      ''command="${config.nix.package}/bin/nix-daemon --stdio",restrict ${framerRootKey}''
    ];
  };

  users.groups.nix-builder = { };

  nix.settings.trusted-users = [ "nix-builder" ];
}
