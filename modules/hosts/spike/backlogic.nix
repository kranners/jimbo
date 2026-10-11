{ inputs, config, ... }:
let
  instance = config.services.backlogic.instances.aaron;
  domain = "backlogic.spike.cute.engineer";
in
{
  imports = [ inputs.backlogic.nixosModules.default ];

  # Keeps serving the store `backlogic-aaron` (the transient user unit this replaces)
  # already keeps at `~/backlogic-data/aaron`, so the move costs no data and the
  # separate `backlogic-runner-aaron` unit, left running as it is, reads the same
  # `runner.json` beside it with no change of its own.
  services.backlogic.instances.aaron = {
    dataDir = "/home/aaron/backlogic-data/aaron";
    port = 4200;
    project = "bowerbird";
    displayName = "Aaron's instance";
    user = "aaron";
  };

  services.caddy.virtualHosts.${domain}.extraConfig = ''
    reverse_proxy ${instance.hostname}:${toString instance.port}
  '';
}
