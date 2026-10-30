{ pkgs, lib, ... }:
let
  python = pkgs.python3Packages;

  photos = pkgs.writers.writePython3Bin "photos" {
    libraries = [
      python.pyicloud
      python.pillow
      python.pillow-heif
    ];
    flakeIgnore = [
      "E402"
      "E501"
    ];
  } (builtins.readFile ./butler-photos/photos.py);

  both = [
    "interactive"
    "cron"
  ];

  private = verb: {
    match = [
      verb
      "**"
    ];
    lanes = both;
    taints = true;
  };
in
{
  assertions = [
    {
      assertion = lib.versionAtLeast python.pyicloud.version "2026.10.1";
      message = "butler's photos needs pyicloud 2026.10.1 or later for its CloudKit Photos service, but nixpkgs has ${python.pyicloud.version}";
    }
  ];

  butler.commands.photos = {
    package = photos;
    description = ''
      Read Aaron's iCloud Photos. Prints JSON, except get, which saves a JPEG to attach and prints its path.
      photos albums | photos recent [count] | photos album <name> [count] | photos on <YYYY-MM-DD> [YYYY-MM-DD] | photos get <id> [small|medium|large]
    '';
    rules = map private [
      "albums"
      "recent"
      "album"
      "on"
      "get"
    ];
    skill = ./butler-skills/photos;
  };
}
