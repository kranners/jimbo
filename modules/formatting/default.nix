{
  pkgs,
  lib,
  host,
  ...
}:
let
  inherit (lib) mkOption types getExe;
  inherit (host) system;

  source = ../..;

  runCheck =
    name: command:
    pkgs.runCommand "check-${name}" { } ''
      ${command}
      touch $out
    '';
in
{
  options = {
    formatter = mkOption {
      type = types.raw;
      default = { };
    };

    checks = mkOption {
      type = types.raw;
      default = { };
    };
  };

  config = {
    formatter.${system} = pkgs.nixfmt-tree;

    checks.${system} = {
      nixfmt = runCheck "nixfmt" ''
        find ${source} -name '*.nix' -exec ${getExe pkgs.nixfmt} --check {} +
      '';

      statix = runCheck "statix" ''
        ${getExe pkgs.statix} check --config ${source} ${source}
      '';

      deadnix = runCheck "deadnix" ''
        ${getExe pkgs.deadnix} --fail ${source}
      '';
    };
  };
}
