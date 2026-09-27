{ host, ... }:
{
  nixosSystemModule = {
    # `tailscale up` is interactive, so the tailnet is joined once by hand.
    services.tailscale = {
      enable = true;

      # OpenClaw runs `tailscale serve` from its user service, which needs
      # operator rights on the daemon.
      extraSetFlags = [ "--operator=${host.username}" ];
    };
  };
}
