{ pkgs, ... }:
let
  weather = pkgs.writers.writePython3Bin "weather" {
    libraries = [ pkgs.python3Packages.tzdata ];
    flakeIgnore = [ "E501" ];
  } (builtins.readFile ./butler-weather/weather.py);

  # Every call sends a place's name or point to Open-Meteo, so it is egress like WebSearch, and a lookup like it.
  view = view: {
    match = [
      view
      "**"
    ];
    lanes = [
      "interactive"
      "cron"
      "call"
    ];
    egress = true;
    lookup = true;
  };
in
{
  butler.commands.weather = {
    package = weather;
    description = ''
      Weather from Open-Meteo, Collingwood by default: current conditions, the next 24 hours, the next 7 days, and whether to ride the e-bike to Work and back.
      weather now [<place>] | weather hourly [<place>] | weather week [<place>] | weather ride [today|tomorrow|YYYY-MM-DD] [<there HH:MM> [<back HH:MM>]]
      A place is a town or suburb, optionally followed by a comma and its state or country, or lat,lng.
    '';
    rules = map view [
      "now"
      "hourly"
      "week"
      "ride"
    ];
  };
}
