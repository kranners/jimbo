{
  config,
  pkgs,
  lib,
  ...
}:
let
  python = pkgs.python3Packages;

  script =
    name: file:
    pkgs.writers.writePython3Bin name
      {
        libraries = [ python.pyicloud ];
        flakeIgnore = [
          "E402"
          "E501"
        ];
      }
      (
        builtins.replaceStrings [ "@memoryAudit@" ] [ (lib.getExe config.butler.memoryAudit) ] (
          builtins.readFile file
        )
      );

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
        lanes = both ++ [ "call" ];
      }
      {
        match = [
          "due"
          "**"
        ];
        lanes = both ++ [ "call" ];
      }
      {
        match = [
          "open"
          "**"
        ];
        lanes = both ++ [ "call" ];
      }
      {
        match = [
          "add"
          "**"
        ];
        # A scheduled run may add reminders too, such as confirmation-sweep's for a booking it put in the calendar, each logged to audit/reminders.
        lanes = both;
        acts = true;
        grant = "reminders";
      }
      {
        match = [
          "complete"
          "**"
        ];
        lanes = [ "interactive" ];
        acts = true;
        grant = "reminders";
      }
    ];
    skill = ./butler-skills/reminders;
  };
}
