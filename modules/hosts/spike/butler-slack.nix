{
  config,
  pkgs,
  lib,
  ...
}:
let
  token = "/var/lib/secrets/butler-slack-token";
  # slack-send's own token, from a second Slack app with the write scopes, loaded by slack-send alone, so the reader
  # and the chat sync, which run unasked, never hold a token that can write.
  writeToken = "/var/lib/secrets/butler-slack-write-token";
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
  # What slack-send's token needs: posting and replying, reacting, opening a DM or group DM with a person and private
  # channels, then finding a channel Aaron is in and a person by handle.
  writeScopes = [
    "chat:write"
    "reactions:write"
    "im:write"
    "mpim:write"
    "groups:write"
  ];
  writeLookupScopes = [
    "channels:read"
    "groups:read"
    "im:read"
    "mpim:read"
    "users:read"
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
      target=${token}
      needed="${lib.concatStringsSep " " scopes}"
      if [ "''${1:-}" = --write ]; then
        target=${writeToken}
        needed="${lib.concatStringsSep " " (writeScopes ++ writeLookupScopes)}"
        read -r -s -p "slack-send's Slack user token, from the writing app (xoxp-..., hidden): " value
        echo
      elif [ "''${1:-}" = --from-index ]; then
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
      for scope in $needed; do
        grep -qx "$scope" <<<"$granted" || missing="$missing $scope"
      done
      if [ -n "$missing" ]; then
        echo "the token lacks:$missing; add them under User Token Scopes, reinstall the app and paste the new token; nothing changed" >&2
        exit 1
      fi
      if [ "$target" = ${token} ]; then
        for scope in ${lib.concatStringsSep " " writeScopes}; do
          if grep -qx "$scope" <<<"$granted"; then
            echo "the reader's token must not write, and this one has $scope; make the reading app's token read-only and give slack-send its own with --write; nothing changed" >&2
            exit 1
          fi
        done
      fi
      printf '%s' "$value" > "$target.new"
      chmod 600 "$target.new"
      mv "$target.new" "$target"
      echo "Slack token for $(jq -r '.user + " in " + .team' <<<"$answer") written to $target"
      optional=""
      for scope in ${lib.concatStringsSep " " optionalScopes}; do
        grep -qx "$scope" <<<"$granted" || optional="$optional $scope"
      done
      [ "$target" != ${token} ] || [ -z "$optional" ] || echo "it works without these read-only scopes, but adding them shows more:$optional"
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
  writeCredential = "/run/credentials/butler.service/slack-write-token";

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

  # The one writer, every verb gated by Aaron's approval like mail-send: see butler-slack/send.py.
  slack-send = pkgs.writers.writePython3Bin "slack-send" { flakeIgnore = [ "E501" ]; } (
    builtins.replaceStrings
      [ "@credential@" "@memoryAudit@" ]
      [ writeCredential (lib.getExe config.butler.memoryAudit) ]
      (builtins.readFile ./butler-slack/send.py)
  );
  # Every verb is one rule: it taints and goes out, and is the outcome `message` to the channel it names, so outside
  # a mission naming that channel Aaron approves each write, its exact channel and text, with a button.
  sendRule = match: {
    inherit match;
    lanes = [ "interactive" ];
    taints = true;
    egress = true;
    outcome = {
      kind = "message";
      to = 1;
    };
  };
in
{
  environment.systemPackages = [ butler-slack-login ];

  # LoadCredential fails butler's start when its source is missing, so an empty placeholder
  # stands in until Aaron writes the token, and the command says it has none.
  systemd.services.butler-slack-token = {
    description = "Create empty placeholders for butler's Slack tokens until they are written";
    unitConfig.ConditionPathExists = [
      "|!${token}"
      "|!${writeToken}"
    ];
    serviceConfig = {
      Type = "oneshot";
      UMask = "0077";
    };
    script = ''
      [ -e ${token} ] || touch ${token}
      [ -e ${writeToken} ] || touch ${writeToken}
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

  butler.commands.slack-send = {
    package = slack-send;
    description = ''
      Write to Aaron's work Slack workspace as Aaron, after he approves the exact channel and text with a button: post, reply in a thread, react, and edit or delete only a message slack-send posted.
      slack-send post <to> | slack-send reply <to> <thread ts> | slack-send react <to> <ts> <emoji> | slack-send edit <to> <ts> | slack-send delete <to> <ts>; post, reply and edit take the text on stdin, about 500 characters at most.
      <to> is #channel-name for a channel Aaron is in, @handle for a DM with one person or @a,@b for a group DM, handles as slack users shows them, so the approval names who it goes to; ids are refused.
    '';
    stdin = true;
    rules = map sendRule [
      [
        "post"
        "*"
      ]
      [
        "reply"
        "*"
        "*"
      ]
      [
        "react"
        "*"
        "*"
        "*"
      ]
      [
        "edit"
        "*"
        "*"
      ]
      [
        "delete"
        "*"
        "*"
      ]
    ];
    credentials.slack-write-token = writeToken;
    skill = ./butler-skills/slack-send;
  };
}
