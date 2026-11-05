{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.butler.workGoogle;
  inherit (config.users.users.butler) home;

  directory = "${home}/.local/share/work-google";
  token = "${directory}/token.json";
  login = "sudo -u butler butler-work-google-login <work address>";

  reader = pkgs.writers.writePython3 "work-google.py" {
    libraries = [ pkgs.python3Packages.tzdata ];
    flakeIgnore = [ "E501" ];
  } (builtins.readFile ./butler-work-google/work_google.py);

  environment = ''
    export WORK_GOOGLE_TOKEN=${token}
    export WORK_GOOGLE_LOGIN=${lib.escapeShellArg login}
    export WORK_GOOGLE_TZ=${config.time.timeZone}
  '';

  work-google = pkgs.writeShellScriptBin "work-google" ''
    ${environment}
    exec ${reader} "$@"
  '';

  butler-work-google-login = pkgs.writeShellScriptBin "butler-work-google-login" ''
    if [ "$(${pkgs.coreutils}/bin/id -un)" != butler ]; then
      echo "run it as butler: ${login}" >&2
      exit 1
    fi
    umask 077
    ${environment}
    exec ${reader} login "$@"
  '';

  both = [
    "interactive"
    "cron"
  ];
in
{
  options.butler.workGoogle = {
    enable = lib.mkEnableOption "butler's read-only work Google mail and calendar, once Aaron's login has stored its token";
    package = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = work-google;
      description = "The reader `mail work` and `calendar work` hand their arguments to.";
    };
  };

  config = lib.mkIf (cfg.enable && config.butler.credentialedTools) {
    environment.systemPackages = [ butler-work-google-login ];

    systemd.tmpfiles.rules = [ "d ${directory} 0700 butler butler -" ];

    # The work rules come first, since the first rule that matches decides:
    # work mail is a conversation's and, through butler.nix's manifest, a scheduled run's, and a call sees the meetings but no mail.
    butler.commands.mail.rules = lib.mkBefore [
      {
        match = [
          "work"
          "**"
        ];
        lanes = [ "interactive" ];
      }
    ];

    butler.commands.calendar.rules = lib.mkBefore [
      {
        match = [
          "work"
          "brief"
          "**"
        ];
        lanes = both ++ [ "call" ];
        taints = true;
      }
      {
        match = [
          "work"
          "agenda"
          "**"
        ];
        lanes = [
          "interactive"
          "call"
        ];
        taints = true;
      }
      {
        match = [
          "work"
          "events"
          "**"
        ];
        lanes = [
          "interactive"
          "call"
        ];
        taints = true;
      }
    ];
  };
}
