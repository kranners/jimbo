{ host, ... }: {
  imports = [
    ./state-versions.nix
    ./work-tools.nix
    ./kanban.nix
  ];

  darwinSystemModule.networking = {
    hostName = host.hostname;
    computerName = host.hostname;
    localHostName = host.hostname;
  };
}
