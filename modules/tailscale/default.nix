{
  nixosSystemModule = {
    # `tailscale up` is interactive, so the tailnet is joined once by hand.
    services.tailscale.enable = true;
  };
}
