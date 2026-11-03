{ pkgs, ... }:
let
  key = "/var/lib/secrets/butler-google-maps-api-key";

  maps = pkgs.writers.writePython3Bin "maps" {
    libraries = [ pkgs.python3Packages.tzdata ];
    flakeIgnore = [ "E501" ];
  } (builtins.readFile ./butler-maps/maps.py);

  # Every call sends its words to Google, so it is egress like WebSearch.
  verb = verb: {
    match = [
      verb
      "**"
    ];
    lanes = [
      "interactive"
      "cron"
      "call"
    ];
    egress = true;
  };
in
{
  # LoadCredential fails butler's start when its source is missing, so an empty placeholder
  # stands in until Aaron writes the key, and the command says it has none.
  systemd.services.butler-google-maps-key = {
    description = "Create an empty placeholder for butler's Google Maps API key until one is written";
    unitConfig.ConditionPathExists = "!${key}";
    serviceConfig = {
      Type = "oneshot";
      UMask = "0077";
    };
    script = ''
      touch ${key}
    '';
  };

  systemd.services.butler = {
    requires = [ "butler-google-maps-key.service" ];
    after = [ "butler-google-maps-key.service" ];
  };

  butler.commands.maps = {
    package = maps;
    description = ''
      Look places up on Google Maps: hours and whether open now, phone, address and rating; search for places; travel times and directions.
      maps place <maps link | name and area> | maps search <query>... [near <place>] [open] | maps route <walk|bike|drive|transit> <from> <to> [depart|arrive <HH:MM | YYYY-MM-DD HH:MM>]
      A place is a Maps link, an address, a name and area, lat,lng or, for route, place_id:ID.
    '';
    rules = map verb [
      "place"
      "search"
      "route"
    ];
    credentials.google-maps-api-key = key;
    skill = ./butler-skills/maps;
  };
}
