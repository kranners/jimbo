{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.butler.outlook;
  inherit (config.users.users.butler) home;

  tokenDirectory = "${home}/.local/share/ortie";
  token = "${tokenDirectory}/outlook.json";
  microsoft = "https://login.microsoftonline.com/consumers/oauth2/v2.0";

  ortieConfig = (pkgs.formats.toml { }).generate "butler-ortie.toml" {
    accounts.outlook = {
      default = true;
      client-id = cfg.clientId;
      grant = "device";
      endpoints = {
        device-authorization = "${microsoft}/devicecode";
        token = "${microsoft}/token";
      };
      scopes = [
        "https://outlook.office.com/IMAP.AccessAsUser.All"
        "https://outlook.office.com/SMTP.Send"
        "offline_access"
      ];
      auto-refresh = true;
      storage.read.command = [
        "${pkgs.coreutils}/bin/cat"
        token
      ];
      storage.write.command = "new=$(${pkgs.coreutils}/bin/mktemp ${tokenDirectory}/.outlook.XXXXXX) && ${pkgs.coreutils}/bin/cat > \"$new\" && ${pkgs.coreutils}/bin/mv \"$new\" ${token}";
    };
  };

  xoauth2 = {
    username = cfg.address;
    token.command = [
      (lib.getExe pkgs.ortie)
      "--config"
      "${ortieConfig}"
      "token"
      "show"
    ];
  };

  butler-outlook-login = pkgs.writeShellApplication {
    name = "butler-outlook-login";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.ortie
    ];
    text = ''
      if [ "$(id -un)" != butler ]; then
        echo "run it as butler: sudo -u butler butler-outlook-login" >&2
        exit 1
      fi
      ortie --config ${ortieConfig} auth get
      ortie --config ${ortieConfig} token inspect
    '';
  };
in
{
  options.butler.outlook = {
    enable = lib.mkEnableOption "butler's Outlook account in mail and mail-send, once butler-outlook-login has stored its token";

    address = lib.mkOption {
      type = lib.types.str;
      description = "The personal Microsoft account's address, which IMAP and SMTP log in as.";
    };

    clientId = lib.mkOption {
      type = lib.types.str;
      description = "The application (client) ID of Aaron's own Entra app for personal Microsoft accounts.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ butler-outlook-login ];

    systemd.tmpfiles.rules = [ "d ${tokenDirectory} 0700 butler butler -" ];

    butler.mail.accounts.outlook.himalaya = {
      email = cfg.address;
      display-name = "Aaron Pierce";
      imap.server = "outlook.office365.com:993";
      imap.sasl.xoauth2 = xoauth2;
      smtp.server = "smtp://smtp-mail.outlook.com:587";
      smtp.starttls = true;
      smtp.sasl.xoauth2 = xoauth2;
      mailbox.alias = {
        inbox = "INBOX";
        archive = "Archive";
      };
    };
  };
}
