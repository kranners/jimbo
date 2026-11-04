{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.nuc.backlogicRunner;
  runnerHome = config.users.users.backlogic-runner.home;
in
{
  options.nuc.backlogicRunner.enable = lib.mkEnableOption ''
    backlogic's runner on the NUC, the same unit spike runs (modules/backlogic-runner), claiming tickets from
    spike's instance over WireGuard, with its caps derived from nuc.memoryGiB and nuc.cores.
    Turn spike's own off in the same change, so only one runner claims tickets
  '';

  config = lib.mkIf cfg.enable {
    backlogicRunner = {
      enable = true;
      url = "http://10.100.0.1:4200";
      inherit (config.nuc) memoryGiB cores;
    };

    # What the runner's sessions find on spike: Claude Code, python3 for repository hooks, a headless Chrome
    # for backlogic's bin/check, and mise's tools, built for other Linuxes, loading through nix-ld.
    programs.nix-ld.enable = true;
    environment.systemPackages = [
      pkgs.claude-code
      pkgs.python3
      pkgs.google-chrome
      pkgs.mise
    ];
    environment.etc."mise/config.toml".source = (pkgs.formats.toml { }).generate "mise-config.toml" {
      tools.deno = "latest";
      settings = {
        python.compile = false;
        trusted_config_paths = [ "${runnerHome}/workspace/backlogic" ];
      };
    };

    # Each check leaves a dead build in the store, so the NUC collects garbage daily, as spike does.
    nix.gc.dates = "daily";
    nix.settings.auto-optimise-store = true;
  };
}
