# The NUC's jobs as spike's worker, each off until Aaron turns it on, in the order the README gives.
{
  imports = [
    ./backlogic-runner.nix
    ./builder.nix
    ./watchdog.nix
    ./backups.nix
  ];
}
