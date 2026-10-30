{
  config,
  lib,
  pkgs,
  ...
}:
let
  serverName = "spike";
  port = 6167;
  homeserver = "http://127.0.0.1:${toString port}";
  ownerName = "aaron";
  owner = "@${ownerName}:${serverName}";

  tuwunel = config.services.matrix-tuwunel;
  tuwunelState = "/var/lib/${tuwunel.stateDirectory}";
  registrationSecret = "${tuwunelState}/registration-shared-secret";
  appserviceDir = "${tuwunelState}/appservices";

  bridge = config.services.mautrix-meta.instances.facebook;
  bot = "@${bridge.settings.appservice.bot.username}:${serverName}";

  doublePuppet = "/var/lib/matrix-double-puppet";

  matrixToken = "/var/lib/secrets/butler-matrix-token";
  matrixPassword = "/var/lib/secrets/butler-matrix-password";

  randomToken = "od -An -vtx1 -N32 /dev/urandom | tr -d ' \\n'";

  matrix-double-puppet = pkgs.writeShellApplication {
    name = "matrix-double-puppet";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      umask 077
      cd ${doublePuppet}
      [ -s as-token ] || ${randomToken} >as-token
      [ -s hs-token ] || ${randomToken} >hs-token
      as_token=$(< as-token)
      hs_token=$(< hs-token)
      printf 'DOUBLE_PUPPET_AS_TOKEN=%s\n' "$as_token" >double-puppet.env
      cat >registration.yaml <<EOF
      id: doublepuppet
      url: null
      as_token: $as_token
      hs_token: $hs_token
      sender_localpart: doublepuppet
      rate_limited: false
      namespaces:
        users:
          - regex: '^${owner}$'
            exclusive: false
      EOF
    '';
  };

  tuwunel-appservices = pkgs.writeShellApplication {
    name = "tuwunel-appservices";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      umask 077
      if [ ! -s ${registrationSecret} ]; then
        ${randomToken} >${registrationSecret}
      fi
      chown ${tuwunel.user}:${tuwunel.group} ${registrationSecret}
      install -d -m 0700 -o ${tuwunel.user} -g ${tuwunel.group} ${appserviceDir}
      install -m 0600 -o ${tuwunel.user} -g ${tuwunel.group} ${bridge.registrationFile} ${appserviceDir}/facebook.yaml
      install -m 0600 -o ${tuwunel.user} -g ${tuwunel.group} ${doublePuppet}/registration.yaml ${appserviceDir}/doublepuppet.yaml
    '';
  };

  messenger-setup = pkgs.writeShellApplication {
    name = "messenger-setup";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.curl
      pkgs.jq
      pkgs.openssl
    ];
    text = ''
      if [ "$(id -u)" -ne 0 ]; then
        echo "messenger-setup: run it with sudo" >&2
        exit 1
      fi

      umask 077
      if [ -s ${matrixToken} ]; then
        status=$(
          curl --silent --output /dev/null --write-out '%{http_code}' \
            --header @<(printf 'Authorization: Bearer %s\n' "$(< ${matrixToken})") \
            ${homeserver}/_matrix/client/v3/account/whoami
        )
        if [ "$status" = 401 ]; then
          echo "The token in ${matrixToken} was revoked; minting a new one"
          rm ${matrixToken}
        fi
      fi
      if [ ! -s ${matrixToken} ]; then
        if [ -s ${matrixPassword} ]; then
          echo "Logging in as ${owner} to mint a new access token into ${matrixToken}"
          response=$(
            jq --null-input --rawfile password ${matrixPassword} \
              '{type: "m.login.password", identifier: {type: "m.id.user", user: "${ownerName}"}, password: $password, initial_device_display_name: "butler"}' \
              | curl --silent --show-error --fail-with-body --data @- ${homeserver}/_matrix/client/v3/login
          )
        else
          echo "Creating ${owner} and minting its access token into ${matrixToken}"
          secret=$(< ${registrationSecret})
          password=$(${randomToken})
          nonce=$(curl --silent --show-error --fail-with-body ${homeserver}/_synapse/admin/v1/register | jq --raw-output .nonce)
          mac=$(printf '%s\0%s\0%s\0notadmin' "$nonce" ${ownerName} "$password" | openssl dgst -sha1 -hmac "$secret" -r | cut -d ' ' -f 1)
          response=$(
            jq --null-input --arg nonce "$nonce" --arg password "$password" --arg mac "$mac" \
              '{nonce: $nonce, username: "${ownerName}", password: $password, admin: false, mac: $mac, initial_device_display_name: "butler"}' \
              | curl --silent --show-error --fail-with-body --data @- ${homeserver}/_synapse/admin/v1/register
          )
          printf '%s' "$password" >${matrixPassword}
        fi
        jq --raw-output --join-output .access_token <<<"$response" >${matrixToken}
      fi

      token=$(< ${matrixToken})
      matrix() {
        curl --silent --show-error --fail-with-body --globoff \
          --header @<(printf 'Authorization: Bearer %s\n' "$token") \
          "$@"
      }
      client=${homeserver}/_matrix/client/v3

      encode() {
        jq --raw-output --null-input --arg value "$1" '$value | @uri'
      }

      room=""
      while read -r candidate; do
        if matrix "$client/rooms/$(encode "$candidate")/joined_members" | jq --exit-status '.joined | keys | sort == (["${owner}", "${bot}"] | sort)' >/dev/null; then
          room=$candidate
          break
        fi
      done < <(matrix "$client/joined_rooms" | jq --raw-output '.joined_rooms[]')
      if [ -z "$room" ]; then
        room=$(
          jq --null-input '{is_direct: true, preset: "trusted_private_chat", invite: ["${bot}"]}' \
            | matrix --data @- "$client/createRoom" \
            | jq --raw-output .room_id
        )
      fi
      path=$(encode "$room")

      filter=$(jq --compact-output --null-input --arg room "$room" \
        '{room: {rooms: [$room], timeline: {limit: 10}, state: {types: []}, ephemeral: {not_types: ["*"]}, account_data: {not_types: ["*"]}}, presence: {not_types: ["*"]}, account_data: {not_types: ["*"]}}')
      replies() {
        jq --raw-output --arg room "$room" \
          '.rooms.join[$room].timeline.events[]? | select(.type == "m.room.message" and .sender == "${bot}") | "bot: \(.content.body)\n"'
      }
      response=$(matrix --get --data-urlencode "filter=$filter" "$client/sync")
      replies <<<"$response"
      since=$(jq --raw-output .next_batch <<<"$response")

      (
        while :; do
          if response=$(matrix --get --data-urlencode "filter=$filter" --data-urlencode "since=$since" --data-urlencode timeout=30000 "$client/sync"); then
            since=$(jq --raw-output .next_batch <<<"$response")
            replies <<<"$response"
          else
            sleep 5
          fi
        done
      ) &
      poller=$!
      trap 'kill "$poller"' EXIT

      echo "Talking to the bridge bot in $room as ${owner}."
      echo "What you type is hidden and sent as one message per line; the bot's replies print here, and Ctrl-D ends."
      echo "Start with: login messenger-lite-android"
      while IFS= read -r -s line; do
        [ -n "$line" ] || continue
        jq --null-input --arg body "$line" '{msgtype: "m.text", body: $body}' \
          | matrix --request PUT --data @- "$client/rooms/$path/send/m.room.message/setup-$(date +%s%N)" >/dev/null
        echo "sent (''${#line} characters)"
      done
    '';
  };
in
{
  services.matrix-tuwunel = {
    enable = true;
    settings.global = {
      server_name = serverName;
      address = [ "127.0.0.1" ];
      port = [ port ];
      allow_federation = false;
      allow_registration = false;
      allow_encryption = false;
      trusted_servers = [ ];
      registration_shared_secret_file = registrationSecret;
      appservice_dir = appserviceDir;
    };
  };

  systemd.services.tuwunel = {
    wants = [ bridge.registrationServiceUnit ];
    after = [ bridge.registrationServiceUnit ];
    serviceConfig.ExecStartPre = "+${lib.getExe tuwunel-appservices}";
  };

  systemd.services.matrix-double-puppet = {
    description = "Generate the appservice token mautrix-meta double-puppets ${owner} with";
    requiredBy = [ bridge.registrationServiceUnit ];
    before = [ bridge.registrationServiceUnit ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      StateDirectory = "matrix-double-puppet";
      StateDirectoryMode = "0700";
      ExecStart = lib.getExe matrix-double-puppet;
    };
  };

  services.mautrix-meta.package = pkgs.mautrix-meta.override { withGoolm = true; };

  services.mautrix-meta.instances.facebook = {
    enable = true;
    registerToSynapse = false;
    environmentFile = "${doublePuppet}/double-puppet.env";
    serviceDependencies = [
      bridge.registrationServiceUnit
      "tuwunel.service"
    ];
    settings = {
      homeserver = {
        domain = serverName;
        address = homeserver;
      };
      appservice.hostname = "127.0.0.1";
      bridge.permissions.${owner} = "admin";
      double_puppet.secrets.${serverName} = "as_token:$DOUBLE_PUPPET_AS_TOKEN";
      encryption = {
        allow = false;
        default = false;
        require = false;
      };
      backfill.enabled = true;
      matrix.federate_rooms = false;
      provisioning.shared_secret = "disable";
    };
  };

  environment.systemPackages = [ messenger-setup ];
}
