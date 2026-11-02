{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.butler.workMail;
  inherit (config.users.users.butler) home;

  tokenDirectory = "${home}/.local/share/ortie";
  token = "${tokenDirectory}/work.json";
  client = "${tokenDirectory}/work-client.toml";

  ortieConfig = (pkgs.formats.toml { }).generate "butler-ortie-work.toml" {
    accounts.work = {
      default = true;
      grant = "authorization-code";
      endpoints = {
        authorization = "https://accounts.google.com/o/oauth2/v2/auth";
        token = "https://oauth2.googleapis.com/token";
        redirection = "http://localhost";
      };
      scopes = [ "https://www.googleapis.com/auth/gmail.readonly" ];
      extras = {
        access_type = "offline";
        prompt = "consent";
      };
      auto-refresh = true;
      storage.read.command = [
        "${pkgs.coreutils}/bin/cat"
        token
      ];
      storage.write.command = "new=$(${pkgs.coreutils}/bin/mktemp ${tokenDirectory}/.work.XXXXXX) && ${pkgs.coreutils}/bin/cat > \"$new\" && ${pkgs.coreutils}/bin/mv \"$new\" ${token}";
    };
  };

  ortie = "ortie --config ${ortieConfig} --config ${client}";

  butler-work-mail-login = pkgs.writeShellApplication {
    name = "butler-work-mail-login";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.jq
      pkgs.ortie
    ];
    text = ''
      if [ "$(id -un)" != butler ]; then
        echo "run it as butler: sudo -u butler butler-work-mail-login" >&2
        exit 1
      fi

      read -r -p "Google OAuth desktop client ID: " client_id
      read -r -s -p "Google OAuth desktop client secret: " client_secret
      echo
      [[ $client_id =~ ^[A-Za-z0-9._-]+$ && $client_secret =~ ^[A-Za-z0-9._-]+$ ]] || {
        echo "that does not look like a Google OAuth client ID and secret" >&2
        exit 1
      }

      umask 077
      new=$(mktemp ${tokenDirectory}/.work-client.XXXXXX)
      printf '[accounts.work]\nclient-id = "%s"\nclient-secret.raw = "%s"\n' "$client_id" "$client_secret" >"$new"
      mv "$new" ${client}

      request=$(${ortie} --json auth get)
      echo
      echo "Open this link in a browser signed in to the work Google account and allow read-only Gmail access:"
      echo
      jq --raw-output .authorization_uri <<<"$request"
      echo
      echo "The browser then fails to load a http://localhost page; that is expected."
      read -r -p "Paste that page's whole address here: " redirected
      ${ortie} auth resume \
        --state="$(jq --raw-output .state <<<"$request")" \
        --pkce="$(jq --raw-output .pkce_code_verifier <<<"$request")" \
        "$redirected"
      ${ortie} token inspect
    '';
  };
in
{
  options.butler.workMail.enable = lib.mkEnableOption "butler's read-only Google Workspace work account in mail, once butler-work-mail-login has stored its token";

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ butler-work-mail-login ];

    systemd.tmpfiles.rules = [ "d ${tokenDirectory} 0700 butler butler -" ];

    butler.mail.accounts.work = {
      readOnly = true;
      himalaya = {
        display-name = "Aaron Pierce";
        gmail.auth.token.command = [
          (lib.getExe pkgs.ortie)
          "--config"
          "${ortieConfig}"
          "--config"
          client
          "token"
          "show"
        ];
        mailbox.alias.inbox = "INBOX";
      };
    };
  };
}
