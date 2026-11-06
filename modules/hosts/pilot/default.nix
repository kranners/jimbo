{ host, ... }: {
  imports = [
    ./state-versions.nix
    ./work-tools.nix
    ./kanban.nix
    ./butler-root.nix
  ];

  darwinSystemModule.networking = {
    hostName = host.hostname;
    computerName = host.hostname;
    localHostName = host.hostname;
  };
}
