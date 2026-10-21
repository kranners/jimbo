{
  config,
  lib,
  pkgs,
  ...
}:
let
  runnerHome = config.users.users.backlogic-runner.home;

  # A unit's path entries are bin directories, so the shims are linked in as one.
  miseShimsOf =
    home:
    pkgs.runCommand "mise-shims" { } ''
      mkdir $out
      ln -s ${home}/.local/share/mise/shims $out/bin
    '';
in
{
  # mise's tools, such as backlogic's Deno and Python, are built for other Linuxes and load through nix-ld.
  programs.nix-ld.enable = true;

  environment.systemPackages = [ pkgs.mise ];

  # mise compiles Python from source by default here, which fails, so it takes the prebuilt one.
  # A shim outside any mise.toml has no version, so Deno defaults to the newest installed, for hooks run elsewhere.
  environment.etc."mise/config.toml".source = (pkgs.formats.toml { }).generate "mise-config.toml" {
    tools.deno = "latest";
    settings = {
      python.compile = false;
      trusted_config_paths = [
        "/home/aaron/workspace/backlogic"
        "${runnerHome}/workspace/backlogic"
      ];
    };
  };

  systemd.services =
    lib.genAttrs
      [
        "claude-remote-control"
        "discord-threads"
      ]
      (_: {
        path = lib.mkAfter [ (miseShimsOf "/home/aaron") ];
      })
    // {
      backlogic-runner-aaron.path = lib.mkAfter [ (miseShimsOf runnerHome) ];
    };
}
