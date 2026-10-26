{
  systemd.settings.Manager = {
    RuntimeWatchdogSec = "30s";
    RebootWatchdogSec = "5min";
  };

  boot.kernel.sysctl = {
    "kernel.panic" = 10;
    "kernel.panic_on_oops" = 1;
    "vm.oom_dump_tasks" = 0;
  };

  nix.settings = {
    min-free = 20 * 1024 * 1024 * 1024;
    max-free = 60 * 1024 * 1024 * 1024;
    auto-optimise-store = true;
  };

  hardware.rasdaemon.enable = true;
}
