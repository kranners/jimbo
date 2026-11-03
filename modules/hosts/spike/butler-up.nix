{ pkgs, ... }:
let
  # The same personal access token the index's Up ingest uses, so nothing new is written by hand.
  token = "/var/lib/secrets/butler-index-up-token";

  up = pkgs.writers.writePython3Bin "up" {
    flakeIgnore = [ "E501" ];
  } (builtins.readFile ./butler-up/up.py);

  both = [
    "interactive"
    "cron"
  ];

  verb = match: {
    inherit match;
    lanes = both;
  };
in
{
  # LoadCredential fails butler's start when its source is missing, so an empty placeholder
  # stands in until the token is written, and the command says it has none.
  systemd.services.butler-up-token = {
    description = "Create an empty placeholder for butler's Up token until one is written";
    unitConfig.ConditionPathExists = "!${token}";
    serviceConfig = {
      Type = "oneshot";
      UMask = "0077";
    };
    script = ''
      touch ${token}
    '';
  };

  # The placeholder would otherwise start the index's ingest with an empty token, which fails.
  systemd.services.butler-index-up.unitConfig.ConditionFileNotEmpty = token;

  systemd.services.butler = {
    requires = [ "butler-up-token.service" ];
    after = [ "butler-up-token.service" ];
  };

  butler.commands.up = {
    private = true;
    package = up;
    description = ''
      Read Aaron's Up bank accounts live, read-only: it cannot transfer, pay or change anything.
      up accounts | up transactions [from YYYY-MM-DD] [to YYYY-MM-DD] [account <name>] [match <text>] [category <id>] [limit N] | up spending <from YYYY-MM-DD> <to YYYY-MM-DD> [account <name>] | up categories
      Dates are Melbourne days, both ends included; limit is 1 to 500, 25 unless given; match searches the description and notes; an account is part of its name.
    '';
    rules = map verb [
      [ "accounts" ]
      [ "categories" ]
      [ "transactions" ]
      [
        "transactions"
        "**"
      ]
      [
        "spending"
        "**"
      ]
    ];
    credentials.up-token = token;
  };
}
