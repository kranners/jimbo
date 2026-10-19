{ host, ... }: {
  imports = [
    ./state-versions.nix
  ];

  darwinSystemModule.networking = {
    hostName = host.hostname;
    computerName = host.hostname;
    localHostName = host.hostname;
  };
}
