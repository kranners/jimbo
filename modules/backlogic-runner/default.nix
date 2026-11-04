{
  # Options only, off by default: spike runs backlogic's runner with them, and the NUC can once its role is on.
  nixosSystemModule.imports = [ ./runner.nix ];
}
