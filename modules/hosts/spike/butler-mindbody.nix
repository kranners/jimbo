{ pkgs, ... }:
let
  mindbody = pkgs.writers.writePython3Bin "mindbody" {
    libraries = [ pkgs.python3Packages.tzdata ];
    flakeIgnore = [ "E501" ];
  } (builtins.readFile ./butler-mindbody/mindbody.py);

  # Every call fetches REVL's public Mindbody schedule and sends nothing of Aaron's, so it is a lookup like WebSearch.
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
  butler.commands.mindbody = {
    package = mindbody;
    description = ''
      REVL Collingwood's class timetable from its public Mindbody schedule: the coming week's classes with coach, spots free and class id. Aaron's own bookings, booking, cancelling and waitlists go through his Mindbody login in your browser, by the mindbody skill.
      mindbody timetable [today|tomorrow|week|<weekday>|YYYY-MM-DD] [<class name words>] | mindbody class <class id> | mindbody link
    '';
    rules = map view [
      "timetable"
      "class"
      "link"
    ];
  };
}
