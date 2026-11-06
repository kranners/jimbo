{ pkgs, lib, ... }:
let
  token = "/var/lib/secrets/butler-slack-token";
  # The index's 6-hourly Slack read has its own token, which Aaron may reuse for live reads when its scopes cover them.
  indexToken = "/var/lib/secrets/butler-index-slack-token";
  scopes = [
    "channels:history"
    "channels:read"
    "groups:history"
    "groups:read"
    "im:history"
    "im:read"
    "mpim:history"
    "mpim:read"
    "search:read"
    "users:read"
  ];
  # Read-only scopes that make the reader fuller without being needed: file, snippet and canvas text, pins, bookmarks and reactions.
  optionalScopes = [
    "files:read"
    "canvases:read"
    "pins:read"
    "bookmarks:read"
    "reactions:read"
    "usergroups:read"
  ];

  # `sudo butler-slack-login` takes Aaron's xoxp- user token hidden on stdin, or `--from-index` reuses the index's,
  # checks it with auth.test and its scopes, writes it mode 600 and asks butler for a restart at its next quiet moment.
  butler-slack-login = pkgs.writeShellApplication {
    name = "butler-slack-login";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.curl
      pkgs.jq
    ];
    text = ''
      if [ "$(id -u)" -ne 0 ]; then
        echo "run it as root: sudo butler-slack-login [--from-index]" >&2
        exit 1
      fi
      umask 077
      if [ "''${1:-}" = --from-index ]; then
        [ -s ${indexToken} ] || { echo "the index has no Slack token either; paste one instead" >&2; exit 1; }
        value=$(< ${indexToken})
      else
        read -r -s -p "Slack user token (xoxp-..., hidden): " value
        echo
      fi
      case "$value" in
        xoxp-*) ;;
        *) echo "that is not a Slack user token (xoxp-...); nothing changed" >&2; exit 1 ;;
      esac
      headers=$(mktemp)
      trap 'rm -f "$headers"' EXIT
      answer=$(curl --silent --show-error --dump-header "$headers" \
        --header @<(printf 'Authorization: Bearer %s\n' "$value") https://slack.com/api/auth.test)
      if [ "$(jq -r .ok <<<"$answer")" != true ]; then
        echo "Slack refused the token: $(jq -r '.error // "unknown error"' <<<"$answer"); nothing changed" >&2
        exit 1
      fi
      granted=$(tr -d '\r' < "$headers" | sed -n 's/^x-oauth-scopes: //Ip' | tr ',' '\n')
      missing=""
      for scope in ${lib.concatStringsSep " " scopes}; do
        grep -qx "$scope" <<<"$granted" || missing="$missing $scope"
      done
      if [ -n "$missing" ]; then
        echo "the token lacks:$missing; add them under User Token Scopes, reinstall the app and paste the new token; nothing changed" >&2
        exit 1
      fi
      printf '%s' "$value" > ${token}.new
      chmod 600 ${token}.new
      mv ${token}.new ${token}
      echo "Slack token for $(jq -r '.user + " in " + .team' <<<"$answer") written"
      optional=""
      for scope in ${lib.concatStringsSep " " optionalScopes}; do
        grep -qx "$scope" <<<"$granted" || optional="$optional $scope"
      done
      [ -z "$optional" ] || echo "it works without these read-only scopes, but adding them shows more:$optional"
      install -d -m 755 /run/butler-restart
      if [ ! -f /run/butler-restart/wanted ]; then
        jq -n --argjson at "$(date +%s%3N)" '{at: $at, trigger: "slack-token", changes: ["Slack token for live reads written"]}' > /run/butler-restart/wanted.tmp
        chmod 644 /run/butler-restart/wanted.tmp
        mv /run/butler-restart/wanted.tmp /run/butler-restart/wanted
      fi
      echo "butler restarts to load it at its next quiet moment"
    '';
  };
  credential = "/run/credentials/butler.service/slack-token";

  both = [
    "interactive"
    "cron"
  ];

  # The reader itself, read-only, rendering each message whole: see butler-slack/slack.py.
  slack = pkgs.writers.writePython3Bin "slack" { flakeIgnore = [ "E501" ]; } (
    builtins.replaceStrings [ "@credential@" ] [ credential ] (
      builtins.readFile ./butler-slack/slack.py
    )
  );
in
{
  environment.systemPackages = [ butler-slack-login ];

  # LoadCredential fails butler's start when its source is missing, so an empty placeholder
  # stands in until Aaron writes the token, and the command says it has none.
  systemd.services.butler-slack-token = {
    description = "Create an empty placeholder for butler's Slack token until one is written";
    unitConfig.ConditionPathExists = "!${token}";
    serviceConfig = {
      Type = "oneshot";
      UMask = "0077";
    };
    script = ''
      touch ${token}
    '';
  };

  systemd.services.butler = {
    requires = [ "butler-slack-token.service" ];
    after = [ "butler-slack-token.service" ];
  };

  butler.commands.slack = {
    private = true;
    package = slack;
    description = ''
      Read Aaron's work Slack workspace, read-only: it cannot post, react or edit.
      slack channels | slack history <channel> [count] | slack dms | slack search <query>... | slack thread <channel> <ts> [after-ts] | slack message <channel> <ts> | slack users | slack scopes
      Every message prints whole, never cut at Slack's "see more": its rich text, any shared message or link preview and, with files:read, its snippets', text files' and canvases' text; thread pages through every reply, reading on after a reply's ts when the output limit stops it, message prints one message, and scopes lists the token's scopes and the read-only ones that would help, never the token.
      A channel is its id, such as C0123ABCD or a DM's D0123ABCD, or a channel's name; count is 1 to 200, 20 unless given.
    '';
    rules = [
      {
        match = [ "channels" ];
        lanes = both;
      }
      {
        match = [ "dms" ];
        lanes = both;
      }
      {
        match = [ "users" ];
        lanes = both;
      }
      {
        match = [
          "history"
          "*"
        ];
        lanes = both;
      }
      {
        match = [
          "history"
          "*"
          "*"
        ];
        lanes = both;
      }
      {
        match = [
          "thread"
          "*"
          "*"
        ];
        lanes = both;
      }
      {
        match = [
          "thread"
          "*"
          "*"
          "*"
        ];
        lanes = both;
      }
      {
        match = [
          "message"
          "*"
          "*"
        ];
        lanes = both;
      }
      {
        match = [ "scopes" ];
        lanes = both;
      }
      {
        match = [
          "search"
          "**"
        ];
        lanes = both;
      }
    ];
    credentials.slack-token = token;
    skill = ./butler-skills/slack;
  };
}
