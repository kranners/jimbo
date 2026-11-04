# `note`, which butler runs in its sandbox, and `butler-notes-write`, which applies its requests outside it.
# The flake check passes a stand-in `ob`, since it never syncs.
{
  pkgs,
  lib,
  ob ? lib.getExe pkgs.obsidian-headless,
}:
{
  note = pkgs.writers.writePython3Bin "note" { flakeIgnore = [ "E501" ]; } (
    builtins.readFile ./note.py
  );

  writer = pkgs.writers.writePython3Bin "butler-notes-write" {
    makeWrapperArgs = [
      "--prefix"
      "PATH"
      ":"
      (lib.makeBinPath [ pkgs.git ])
      "--set"
      "OB"
      ob
    ];
    flakeIgnore = [ "E501" ];
  } (builtins.readFile ./notes_write.py);
}
