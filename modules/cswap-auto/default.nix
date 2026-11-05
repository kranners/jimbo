# `cswap auto` as the launchd agent `local.cswap-auto`, switching Claude accounts as each nears its limit.
# It runs in the gui domain so cswap reaches the login keychain.
# cswap itself is uv's, installed by modules/claude, so the agent only names its path.
# The label matches the plist once made by hand, which home-manager unloads and overwrites on the first switch.
{
  lib,
  config,
  host,
  ...
}:
let
  inherit (lib) mkOption types;
  cfg = config.cswapAuto;
in
{
  options.cswapAuto = {
    enable = mkOption {
      description = "Whether to run `cswap auto` as a launchd agent on this Mac.";
      type = types.bool;
      default = host.hostname == "pilot";
    };

    program = mkOption {
      description = "Path of the cswap executable, which uv installs outside Nix.";
      type = types.str;
      default = "/Users/${host.username}/.local/bin/cswap";
    };

    strategy = mkOption {
      description = "Account choice strategy passed to `cswap auto --strategy`.";
      type = types.str;
      default = "best";
    };

    threshold = mkOption {
      description = "Session usage percentage at which cswap switches account.";
      type = types.ints.between 1 100;
      default = 90;
    };

    weeklyThreshold = mkOption {
      description = "Weekly usage percentage at which cswap switches account.";
      type = types.ints.between 1 100;
      default = 95;
    };
  };

  config.darwinHomeModule =
    { config, ... }:
    {
      launchd.agents.cswap-auto = lib.mkIf cfg.enable {
        enable = true;
        config = {
          Label = "local.cswap-auto";
          ProgramArguments = [
            cfg.program
            "auto"
            "--strategy"
            cfg.strategy
            "--threshold"
            (toString cfg.threshold)
            "--weekly-threshold"
            (toString cfg.weeklyThreshold)
          ];
          EnvironmentVariables.PATH = lib.concatStringsSep ":" [
            "${config.home.homeDirectory}/.local/bin"
            "/etc/profiles/per-user/${config.home.username}/bin"
            "/usr/bin"
            "/bin"
          ];
          RunAtLoad = true;
          KeepAlive = true;
          ThrottleInterval = 30;
          StandardOutPath = "${config.home.homeDirectory}/.local/state/cswap-auto.log";
          StandardErrorPath = "${config.home.homeDirectory}/.local/state/cswap-auto.log";
        };
      };
    };
}
