{ lib, pkgs, ... }:
let
  # A unit's path entries are bin directories, so the shims are linked in as one.
  miseShims = pkgs.runCommand "mise-shims" { } ''
    mkdir $out
    ln -s /home/aaron/.local/share/mise/shims $out/bin
  '';
in
{
  # mise's tools, such as backlogic's Deno and Python, are built for other Linuxes and load through nix-ld.
  programs.nix-ld.enable = true;

  environment.systemPackages = [ pkgs.mise ];

  systemd.services = lib.genAttrs [ "claude-remote-control" "discord-threads" ] (_: {
    path = lib.mkAfter [ miseShims ];
  });
}
