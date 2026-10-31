{ pkgs, lib, ... }:
let
  python = pkgs.python3Packages;

  script =
    name: file:
    pkgs.writers.writePython3Bin name {
      libraries = [ python.pyicloud ];
      flakeIgnore = [
        "E402"
        "E501"
      ];
    } (builtins.readFile file);

  reminders = script "reminders" ./butler-reminders/reminders.py;
  butler-icloud-login = script "butler-icloud-login" ./butler-reminders/icloud_login.py;

  both = [
    "interactive"
    "cron"
  ];
in
{
  assertions = [
    {
      assertion = lib.versionAtLeast python.pyicloud.version "2026.10.1";
      message = "butler's reminders needs pyicloud 2026.10.1 or later for its CloudKit Reminders service, but nixpkgs has ${python.pyicloud.version}";
    }
  ];

  environment.systemPackages = [ butler-icloud-login ];

  butler.commands.reminders = {
    package = reminders;
    description = ''
      Read and add Aaron's Apple Reminders through iCloud. Prints JSON.
      reminders lists | reminders due [days] | reminders open [list title] | reminders add <list title> <title> [YYYY-MM-DD[THH:MM]] | reminders complete <id>
    '';
    rules = [
      {
        match = [ "lists" ];
        lanes = both;
      }
      {
        match = [
          "due"
          "**"
        ];
        lanes = both;
      }
      {
        match = [
          "open"
          "**"
        ];
        lanes = both;
      }
      {
        match = [
          "add"
          "**"
        ];
        lanes = [ "interactive" ];
      }
      {
        match = [
          "complete"
          "**"
        ];
        lanes = [ "interactive" ];
      }
    ];
    skill = ./butler-skills/reminders;
  };
}
